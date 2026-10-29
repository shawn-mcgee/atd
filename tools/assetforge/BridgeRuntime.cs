using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using UnityEngine;

// Loaded only by the patched copy. Tick is called on Unity's main thread.
public static class AssetForgeBridge
{
    [Serializable] public class Job {
        public string id;
        public string script;
        public string operation = "build";
        public bool merge = false;
        public float scale = 100;
    }
    [Serializable] public class Result {
        public string id;
        public bool success;
        public string error;
        public string model;
        public string glb;
        public int blocks;
        public string[] messages;
    }
    [Serializable] public class Catalog { public string[] blocks; }
    [Serializable] public class Status {
        public int pid;
        public string version = "0.1.0";
        public string state;
        public string utc;
        public string job;
        public int blocks;
    }
    static string root;
    static string forcedExport;
    static bool initialized;
    static bool collecting;
    static readonly List<string> messages = new List<string>();
    static readonly HashSet<string> blockIds = new HashSet<string>(StringComparer.Ordinal);
    static float nextPoll;
    static float nextHeartbeat;
    static Job current;
    static string running;
    static int phase;
    static int waitFrame;

    public static string ChooseExportPath(object browser, string title, string extension) {
        if (forcedExport != null) return forcedExport;
        return (string)browser.GetType().GetMethod("SaveFile", new Type[] { typeof(string), typeof(string) })
            .Invoke(browser, new object[] { title, extension });
    }

    public static void ValidateBlock(string id) {
        if (collecting && !blockIds.Contains(id)) throw new Exception("Unknown block ID: " + id + ". Consult Bridge/catalog.json.");
    }

    static void AtomicJson(string path, object value) {
        string tmp = path + ".tmp";
        File.WriteAllText(tmp, JsonUtility.ToJson(value, true));
        if (File.Exists(path)) File.Delete(path);
        File.Move(tmp, path);
    }

    static void LogMessage(string message, string stack, LogType type) {
        if (collecting && messages.Count < 100 && (type == LogType.Error || type == LogType.Exception || type == LogType.Warning))
            messages.Add(type + ": " + message);
    }

    static void Heartbeat() {
        AtomicJson(Path.Combine(root, "status.json"), new Status {
            pid = System.Diagnostics.Process.GetCurrentProcess().Id,
            state = current == null ? "ready" : "busy",
            utc = DateTime.UtcNow.ToString("o"), job = current == null ? null : current.id,
            blocks = Collections.blocks.Count
        });
    }

    static void Initialize() {
        root = Path.Combine(Path.GetDirectoryName(Application.dataPath), "Bridge");
        foreach (string part in new string[] { "queue", "running", "results", "archive", "artifacts" })
            Directory.CreateDirectory(Path.Combine(root, part));
        // Never replay a job interrupted by a crash: report it for explicit resubmission.
        foreach (string abandoned in Directory.GetFiles(Path.Combine(root, "running"), "*.json")) {
            string id = Path.GetFileNameWithoutExtension(abandoned);
            AtomicJson(Path.Combine(root, "results", id + ".json"), new Result {
                id = id, success = false, error = "Worker stopped during this job; submit a new job."
            });
            File.Move(abandoned, Path.Combine(root, "archive", id + ".interrupted-" + DateTime.UtcNow.Ticks + ".json"));
        }
        List<string> names = new List<string>();
        foreach (Block block in Collections.blocks) {
            string id = block.collection + "/" + block.type;
            names.Add(id); blockIds.Add(id);
        }
        names.Sort(StringComparer.Ordinal);
        AtomicJson(Path.Combine(root, "catalog.json"), new Catalog { blocks = names.ToArray() });
        Application.runInBackground = true;
        Application.targetFrameRate = 15;
        Application.logMessageReceived += LogMessage;
        initialized = true;
        Heartbeat();
    }

    public static void Tick() {
        // Startup loading happens in Awake; wait until the scene and library are usable.
        if (Time.realtimeSinceStartup < 3 || Collections.blocks == null || Collections.blocks.Count == 0 ||
            Project.instance == null || Procedural.bridge == null || !Global.elements.ContainsKey("workbench")) return;
        try {
            if (!initialized) Initialize();
            if (Time.realtimeSinceStartup >= nextHeartbeat) {
                Heartbeat(); nextHeartbeat = Time.realtimeSinceStartup + 2;
            }
            if (current != null) {
                if (Time.frameCount <= waitFrame) return;
                if (phase == 1) {
                    // Use a fresh Lua VM for each job, so globals and errors cannot leak between jobs.
                    LuaBridge lua = new LuaBridge();
                    lua.AddObject("forge", new Forge());
                    lua.ExecuteCode(File.ReadAllText(current.script));
                    phase = 2; waitFrame = Time.frameCount + 2;
                } else CompleteBuild();
                return;
            }
            if (Time.realtimeSinceStartup < nextPoll) return;
            nextPoll = Time.realtimeSinceStartup + 0.5f;
            string[] files = Directory.GetFiles(Path.Combine(root, "queue"), "*.json");
            Array.Sort(files, StringComparer.Ordinal);
            if (files.Length == 0) return;
            string queued = files[0];
            string id = Path.GetFileNameWithoutExtension(queued);
            running = Path.Combine(root, "running", Path.GetFileName(queued));
            File.Move(queued, running);
            current = new Job { id = id };
            Job parsed = JsonUtility.FromJson<Job>(File.ReadAllText(running));
            if (parsed == null || parsed.id != id || id.Length != 32 || !IsHex(id)) throw new Exception("Invalid job ID.");
            current = parsed;
            if (current.operation != "build") throw new Exception("Unknown operation.");
            if (!Path.IsPathRooted(current.script) || !File.Exists(current.script)) throw new Exception("Script must be an existing absolute path.");
            if (current.scale <= 0 || float.IsNaN(current.scale) || float.IsInfinity(current.scale)) throw new Exception("Scale must be positive and finite.");
            messages.Clear(); collecting = true;
            // This is a dedicated worker: replace its scene, without save prompts or asynchronous clear.
            Selection.Clear();
            Transform bench = Global.elements["workbench"];
            for (int i = bench.childCount - 1; i >= 0; i--) UnityEngine.Object.Destroy(bench.GetChild(i).gameObject);
            phase = 1; waitFrame = Time.frameCount + 2;
            Heartbeat();
        } catch (Exception error) {
            if (current != null) Finish(new Result { id = current.id, success = false, error = error.ToString(), messages = messages.ToArray() });
            else { Debug.LogError("Asset Forge Bridge: " + error); nextPoll = Time.realtimeSinceStartup + 5; }
        }
    }

    static bool IsHex(string value) {
        foreach (char c in value) if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
        return true;
    }

    static void CompleteBuild() {
        int count = Global.SceneBlocks().Count;
        if (count == 0) throw new Exception("Script created no blocks. Check catalog.json for valid block IDs.");
        foreach (string message in messages)
            if (message.StartsWith("Error:") || message.StartsWith("Exception:")) throw new Exception("Unity reported: " + message);
        string folder = Path.Combine(root, "artifacts", current.id);
        Directory.CreateDirectory(folder);
        string model = Path.Combine(folder, "model.model");
        string glb = Path.Combine(folder, "model.glb");
        Project.SaveFile(model, true);
        forcedExport = glb;
        try { Export.ExportModel(3, current.merge, true, false, 0, current.scale, 0, false); }
        finally { forcedExport = null; }
        if (!File.Exists(model) || !File.Exists(glb) || new FileInfo(glb).Length < 20)
            throw new Exception("Exporter did not produce the expected files.");
        Finish(new Result { id = current.id, success = true, model = model, glb = glb,
            blocks = count, messages = messages.ToArray() });
    }

    static void Finish(Result result) {
        collecting = false;
        AtomicJson(Path.Combine(root, "results", Path.GetFileNameWithoutExtension(running) + ".json"), result);
        File.Move(running, Path.Combine(root, "archive", Path.GetFileName(running)));
        current = null; running = null; phase = 0;
        Heartbeat();
    }
}
