# Against the Darkness

[Play the current browser alpha](https://shawn-mcgee.github.io/atd/) | [Versioned URL](https://shawn-mcgee.github.io/atd/v3/)

- **[v3/](v3/README.md)** ? active Godot 3D browser project, mechanics specification, configuration, art, and developer documentation. Open `v3/project.godot` in Godot.
- **v1/** ? preserved legacy game. It is not the default deployment.

The failed experiment has been removed. New development belongs in `v3/`.

```sh
cd v3
npm ci
python tools/setup-engine.py
npm test
npm run export:web
npm run serve
```

The browser-alpha deployment workflow builds from `v3/` and publishes the same new build at `/` and `/v3/`. An already-exported legacy build can optionally be staged at `/v1/`; it is disabled by default. See [deployment details](v3/docs/engine-and-distribution.md). Desktop exports remain deferred.

Full simulation and browser tests run locally, on pull requests, or via the separate manual **Browser alpha tests** workflow. They do not gate deployment. Compilation/export failures still stop a release.
