extends RefCounted
const Actor = preload("res://core/actor.gd")
## Canonical ATD1 state bytes. Keyset IDs are local to each snapshot, assigned
## during sorted-key traversal. No identity, cache history or platform enters it.
const MAX_BYTES := 16777216
const MAX_ITEMS := 1000000
const HEADER := [65, 84, 68, 1]

class Writer:
	extends RefCounted
	# Cache immutable key metadata only. Wire schema IDs remain local to each
	# writer, and exact membership is checked before reusing an ordering.
	static var keysets: Dictionary = {}
	static var large_keysets: Array = []
	var data := PackedByteArray(HEADER)
	var schemas: Dictionary = {}
	var ok := true

	func count(value: int) -> void:
		while value >= 128:
			data.append((value & 127) | 128); value >>= 7
		data.append(value)

	func text(value: String) -> void:
		var encoded := value.to_utf8_buffer()
		if encoded.has(0): ok = false; return
		count(encoded.size()); data.append_array(encoded)

	func integer(value: int) -> void:
		if value >= -64 and value <= 175: data.append(value + 80)
		else:
			data.append(3); var offset := data.size(); data.resize(offset + 8); data.encode_s64(offset, value)

	func keyset(value: Dictionary) -> Dictionary:
		var size := value.size()
		var candidates: Array = keysets.get(size, []) if size <= 64 else large_keysets
		for candidate in candidates:
			if candidate.ordered.size() == size and value.has_all(candidate.ordered): return candidate
		var ordered: Array = []
		for key in value:
			if not key is String and not key is StringName: ok = false; return {}
			ordered.append([str(key), key])
		ordered.sort_custom(func(a, b): return a[0] < b[0])
		var metadata := Writer.new()
		metadata.data.clear(); metadata.count(size)
		var keys: Array = []
		for pair in ordered: metadata.text(pair[0]); keys.append(pair[1])
		if not metadata.ok: ok = false; return {}
		var result := {"ordered": keys, "bytes": metadata.data, "signature": metadata.data.hex_encode()}
		if candidates.size() >= 4: candidates.pop_front()
		candidates.append(result)
		if size <= 64: keysets[size] = candidates
		return result

	func write(value, depth: int = 0) -> void:
		if not ok: return
		if value is Actor: value = value.to_dict()
		if depth > 128 or data.size() > MAX_BYTES: ok = false; return
		if value == null: data.append(0)
		elif value is bool: data.append(2 if value else 1)
		elif value is int: integer(value)
		elif value is float:
			if not is_finite(value): ok = false; return
			if value == floor(value) and value >= -9223372036854775808.0 and value < 9223372036854775808.0: integer(int(value))
			else:
				data.append(10); var offset := data.size(); data.resize(offset + 8); data.encode_double(offset, value)
		elif value is String or value is StringName: data.append(4); text(str(value))
		elif value is Array:
			if value.size() > MAX_ITEMS: ok = false; return
			data.append(5); count(value.size())
			for item in value: write(item, depth + 1)
		elif value is Dictionary:
			if value.is_empty(): data.append(8); return
			if value.size() > MAX_ITEMS: ok = false; return
			var layout := keyset(value)
			if not ok: return
			if value.size() <= 64:
				var signature: String = layout.signature
				if schemas.has(signature): data.append(7); count(int(schemas[signature]))
				else:
					schemas[signature] = schemas.size(); data.append(6); data.append_array(layout.bytes)
			else: data.append(9); data.append_array(layout.bytes)
			for key in layout.ordered: write(value[key], depth + 1)
		else: ok = false

class Reader:
	extends RefCounted
	var data: PackedByteArray
	var at := 4
	var schemas: Array = []
	var ok := true

	func count() -> int:
		var value := 0
		for shift in range(0, 35, 7):
			if at >= data.size(): ok = false; return 0
			var byte := int(data[at]); at += 1
			value |= (byte & 127) << shift
			if byte < 128:
				if value > MAX_BYTES or (shift > 0 and byte == 0): ok = false
				return value
		ok = false; return 0

	func text() -> String:
		var size := count()
		if not ok or size > data.size() - at: ok = false; return ""
		var bytes := data.slice(at, at + size); at += size
		# Validate before conversion, so malformed checkpoints do not emit engine
		# Unicode errors or silently replace code points.
		var i := 0
		while i < bytes.size():
			var lead := int(bytes[i]); i += 1
			if lead == 0: ok = false; return ""
			if lead < 128: continue
			var following := 1 if lead >= 194 and lead <= 223 else 2 if lead >= 224 and lead <= 239 else 3 if lead >= 240 and lead <= 244 else -1
			if following < 0 or following > bytes.size() - i: ok = false; return ""
			var second := int(bytes[i])
			if (lead == 224 and second < 160) or (lead == 237 and second >= 160) or (lead == 240 and second < 144) or (lead == 244 and second >= 144): ok = false; return ""
			for j in following:
				if bytes[i + j] < 128 or bytes[i + j] > 191: ok = false; return ""
			i += following
		return bytes.get_string_from_utf8()

	func read(depth: int = 0):
		if not ok or depth > 128 or at >= data.size(): ok = false; return null
		var tag := int(data[at]); at += 1
		if tag >= 16: return tag - 80
		match tag:
			0: return null
			1: return false
			2: return true
			3, 10:
				if data.size() - at < 8: ok = false; return null
				if tag == 3:
					var integer := data.decode_s64(at); at += 8; return integer
				var value := data.decode_double(at); at += 8
				if not is_finite(value): ok = false
				return value
			4: return text()
			5:
				var size := count()
				if size > MAX_ITEMS or size > data.size() - at: ok = false; return null
				var result: Array = []
				for i in size:
					result.append(read(depth + 1))
					if not ok: return null
				return result
			8: return {}
			6, 7, 9:
				var keys: Array = []
				if tag == 7:
					var id := count()
					if not ok or id >= schemas.size(): ok = false; return null
					keys = schemas[id]
				else:
					var size := count()
					if size == 0 or size > MAX_ITEMS or size > data.size() - at or (tag == 6 and size > 64) or (tag == 9 and size <= 64): ok = false; return null
					for i in size:
						var key := text()
						if not ok or (i > 0 and key <= str(keys.back())): ok = false; return null
						keys.append(key)
					if tag == 6: schemas.append(keys)
				var result: Dictionary = {}
				for key in keys:
					result[key] = read(depth + 1)
					if not ok: return null
				return result
		ok = false; return null

static func pack(state: Dictionary) -> PackedByteArray:
	var writer := Writer.new(); writer.write(state)
	return writer.data if writer.ok and writer.data.size() <= MAX_BYTES else PackedByteArray()

static func hash_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256); context.update(bytes)
	return context.finish().hex_encode()

static func unpack(bytes: PackedByteArray):
	if bytes.size() < 5 or bytes.size() > MAX_BYTES or bytes.slice(0, 4) != PackedByteArray(HEADER): return null
	var reader := Reader.new(); reader.data = bytes
	var state = reader.read()
	return state if reader.ok and reader.at == bytes.size() and state is Dictionary else null
