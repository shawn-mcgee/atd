// ATD1 canonical state encoder. Included after the adapter's API/Variant helpers.
// Schema IDs are local to this traversal; persistent caches never assign wire IDs.
struct StateWriter {
    Kernel &kernel;
    std::vector<uint8_t> &out;
    std::unordered_map<std::string, uint32_t> schemas;
    static constexpr size_t max_bytes = 16777216, max_items = 1000000;
    StateWriter(Kernel &kernel) : kernel(kernel), out(kernel.packed) { out.clear(); out.reserve(131072); out.insert(out.end(), {65,84,68,1}); }
    static void count(std::string &bytes, uint32_t value) {
        while (value >= 128) { bytes.push_back(static_cast<char>((value & 127) | 128)); value >>= 7; }
        bytes.push_back(static_cast<char>(value));
    }
    void count(uint32_t value) {
        while (value >= 128) { out.push_back(static_cast<uint8_t>((value & 127) | 128)); value >>= 7; }
        out.push_back(static_cast<uint8_t>(value));
    }
    void bits(uint64_t value) {
        size_t at = out.size(); out.resize(at + 8);
        for (size_t i = 0; i < 8; ++i) out[at + i] = static_cast<uint8_t>(value >> (i * 8));
    }
    void integer(int64_t value) {
        if (value >= -64 && value <= 175) out.push_back(static_cast<uint8_t>(value + 80));
        else { out.push_back(3); bits(static_cast<uint64_t>(value)); }
    }
    void text(const std::string &value) { count(static_cast<uint32_t>(value.size())); out.insert(out.end(), value.begin(), value.end()); }
    bool write(GDExtensionConstVariantPtr value, unsigned depth = 0) {
        if (depth > 128 || out.size() > max_bytes) return false;
        switch (api.type(value)) {
            case GDEXTENSION_VARIANT_TYPE_NIL: out.push_back(0); return true;
            case GDEXTENSION_VARIANT_TYPE_BOOL: {
                GDExtensionBool b; api.to(GDEXTENSION_VARIANT_TYPE_BOOL)(&b, const_cast<void *>(value)); out.push_back(b ? 2 : 1); return true;
            }
            case GDEXTENSION_VARIANT_TYPE_INT: integer(::integer(value)); return true;
            case GDEXTENSION_VARIANT_TYPE_FLOAT: {
                double n; api.to(GDEXTENSION_VARIANT_TYPE_FLOAT)(&n, const_cast<void *>(value));
                if (!std::isfinite(n)) return false;
                if (n == std::floor(n) && n >= -9223372036854775808.0 && n < 9223372036854775808.0) integer(static_cast<int64_t>(n));
                else { uint64_t encoded; std::memcpy(&encoded, &n, 8); out.push_back(10); bits(encoded); }
                return true;
            }
            case GDEXTENSION_VARIANT_TYPE_STRING:
            case GDEXTENSION_VARIANT_TYPE_STRING_NAME: {
                const auto &encoded = key_text(kernel, value);
                if (encoded.size() > max_bytes || encoded.find('\0') != std::string::npos) return false;
                out.push_back(4); text(encoded); return true;
            }
            case GDEXTENSION_VARIANT_TYPE_ARRAY: {
                auto count_value = count_of(value);
                if (count_value < 0 || count_value > static_cast<int64_t>(max_items)) return false;
                out.push_back(5); count(static_cast<uint32_t>(count_value));
                if (!count_value) return true;
                Builtin array(GDEXTENSION_VARIANT_TYPE_ARRAY, value);
                for (int64_t i = 0; i < count_value; ++i) if (!write(api.array_index(&array.storage, i), depth + 1)) return false;
                return true;
            }
            case GDEXTENSION_VARIANT_TYPE_DICTIONARY: return dictionary(value, depth);
            default: return false;
        }
    }
    bool dictionary(GDExtensionConstVariantPtr value, unsigned depth) {
        int64_t size = count_of(value);
        if (!size) { out.push_back(8); return true; }
        if (size < 0 || size > static_cast<int64_t>(max_items)) return false;
        Builtin dictionary(GDEXTENSION_VARIANT_TYPE_DICTIONARY, value);
        const Schema *schema = nullptr;
        std::shared_ptr<Schema> held;
        if (size > 64) for (size_t i = 0; i < kernel.large_schemas.size(); ++i) {
            const auto &candidate = kernel.large_schemas[i];
            if (static_cast<int64_t>(candidate->ordered.size()) != size) continue;
            const void *arguments[] = {&candidate->keys}; GDExtensionBool contains = false;
            dictionary_has_all(&dictionary.storage, arguments, &contains, 1);
            if (!contains) continue;
            held = candidate; schema = held.get();
            kernel.large_schemas.erase(kernel.large_schemas.begin() + i); kernel.large_schemas.push_back(held);
            break;
        }
        auto found = kernel.schemas.find(size);
        if (!schema && found != kernel.schemas.end()) for (const auto &candidate : found->second) {
            const void *arguments[] = {&candidate->keys}; GDExtensionBool contains = false;
            dictionary_has_all(&dictionary.storage, arguments, &contains, 1);
            if (contains) { schema = candidate.get(); break; }
        }
        std::unique_ptr<Schema> temporary;
        if (!schema) {
            Storage keys{}; GDExtensionCallError error{}; api.call(const_cast<void *>(value), &keys_name, nullptr, 0, &keys, &error);
            Builtin array(GDEXTENSION_VARIANT_TYPE_ARRAY, &keys);
            std::vector<std::pair<const std::string *, int64_t>> ordered; ordered.reserve(static_cast<size_t>(size));
            for (int64_t i = 0; i < size; ++i) {
                auto key = api.array_index(&array.storage, i); auto type = api.type(key);
                if (type != GDEXTENSION_VARIANT_TYPE_STRING && type != GDEXTENSION_VARIANT_TYPE_STRING_NAME) { api.destroy(&keys); return false; }
                const auto &encoded = key_text(kernel, key);
                if (std::any_of(encoded.begin(), encoded.end(), [](unsigned char c) { return c == 0 || c >= 128; })) { api.destroy(&keys); return false; }
                ordered.emplace_back(&encoded, i);
            }
            std::sort(ordered.begin(), ordered.end(), [](const auto &a, const auto &b) { return *a.first < *b.first; });
            if (size > 64) {
                // A bounded exact-keyset cache skips repeated sorting/conversion
                // for stable exploration maps. Hold parents across nested cache
                // eviction; large dictionaries still never consume wire IDs.
                held = std::make_shared<Schema>(&keys, ordered); schema = held.get();
                kernel.large_schemas.push_back(held);
                if (kernel.large_schemas.size() > 4) kernel.large_schemas.erase(kernel.large_schemas.begin());
                api.destroy(&keys);
            } else {
                temporary = std::make_unique<Schema>(&keys, ordered); api.destroy(&keys);
                schema = temporary.get();
                if (kernel.schemas[size].size() < 4) kernel.schemas[size].push_back(std::move(temporary));
            }
        }
        if (schema->signature.empty()) {
            auto &signature = schema->signature; count(signature, static_cast<uint32_t>(size));
            for (const auto &key : schema->ordered) {
                if (std::any_of(key->text.begin(), key->text.end(), [](unsigned char c) { return c == 0 || c >= 128; })) { signature.clear(); return false; }
                count(signature, static_cast<uint32_t>(key->text.size())); signature.append(key->text);
            }
        }
        if (size <= 64) {
            auto known = schemas.find(schema->signature);
            if (known != schemas.end()) { out.push_back(7); count(known->second); }
            else {
                schemas.emplace(schema->signature, static_cast<uint32_t>(schemas.size())); out.push_back(6);
                out.insert(out.end(), schema->signature.begin(), schema->signature.end());
            }
        } else { out.push_back(9); out.insert(out.end(), schema->signature.begin(), schema->signature.end()); }
        for (const auto &key : schema->ordered) if (!write(api.dictionary_index(&dictionary.storage, &key->value), depth + 1)) return false;
        return true;
    }
};

void state_pack(Kernel &kernel, GDExtensionConstVariantPtr state, GDExtensionVariantPtr result) {
    if (kernel.key_count > 8192) { kernel.keys.clear(); kernel.key_count = 0; }
    StateWriter writer(kernel);
    if (!writer.write(state) || writer.out.size() > StateWriter::max_bytes) writer.out.clear();
    Storage packed{}; api.constructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 0)(&packed, nullptr);
    int64_t length = static_cast<int64_t>(writer.out.size()), error = 0; const void *arguments[] = {&length}; byte_resize(&packed, arguments, &error, 1);
    if (length && !error) std::memcpy(api.byte_index(&packed, 0), writer.out.data(), writer.out.size());
    api.from(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)(result, &packed); api.destructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)(&packed);
}
