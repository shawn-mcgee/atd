// ATD1 decoder. Same limits and validation as core/state_codec.gd; no scene APIs.
struct StateReader {
    const uint8_t *data;
    size_t size, at = 4;
    bool ok = true;
    using Keys = std::vector<std::unique_ptr<CachedKey>>;
    std::vector<std::shared_ptr<Keys>> schemas;
    StateReader(const uint8_t *data, size_t size) : data(data), size(size) {}
    uint32_t count() {
        uint64_t value = 0;
        for (unsigned shift = 0; shift < 35; shift += 7) {
            if (at == size) { ok = false; return 0; }
            uint8_t byte = data[at++]; value |= static_cast<uint64_t>(byte & 127) << shift;
            if (byte < 128) {
                if (value > StateWriter::max_bytes || (shift && !byte)) ok = false;
                return static_cast<uint32_t>(value);
            }
        }
        ok = false; return 0;
    }
    static bool utf8(const uint8_t *bytes, size_t length) {
        size_t i = 0;
        while (i < length) {
            uint8_t lead = bytes[i++];
            if (!lead) return false;
            if (lead < 128) continue;
            int following = lead >= 194 && lead <= 223 ? 1 : lead >= 224 && lead <= 239 ? 2 : lead >= 240 && lead <= 244 ? 3 : -1;
            if (following < 0 || static_cast<size_t>(following) > length - i) return false;
            uint8_t second = bytes[i];
            if ((lead == 224 && second < 160) || (lead == 237 && second >= 160) || (lead == 240 && second < 144) || (lead == 244 && second >= 144)) return false;
            for (int j = 0; j < following; ++j) if (bytes[i + j] < 128 || bytes[i + j] > 191) return false;
            i += static_cast<size_t>(following);
        }
        return true;
    }
    void replace(GDExtensionVariantPtr value, GDExtensionVariantType type, void *raw) {
        api.destroy(value); variant_from[type](value, raw);
    }
    bool text(GDExtensionVariantPtr result, std::string *encoded = nullptr) {
        uint32_t length = count();
        if (!ok || length > size - at || !utf8(data + at, length)) return ok = false;
        Storage string{};
        auto error = api.string_len(&string, reinterpret_cast<const char *>(data + at), length);
        if (!error) {
            replace(result, GDEXTENSION_VARIANT_TYPE_STRING, &string);
            if (encoded) encoded->assign(reinterpret_cast<const char *>(data + at), length);
        }
        destroy_type[GDEXTENSION_VARIANT_TYPE_STRING](&string); at += length;
        return ok = error == 0;
    }
    bool read(GDExtensionVariantPtr result, unsigned depth = 0) {
        if (!ok || depth > 128 || at >= size) return ok = false;
        uint8_t tag = data[at++];
        if (tag >= 16) { int64_t n = static_cast<int64_t>(tag) - 80; replace(result, GDEXTENSION_VARIANT_TYPE_INT, &n); return true; }
        switch (tag) {
            case 0: api.destroy(result); api.nil(result); return true;
            case 1: case 2: { GDExtensionBool b = tag == 2; replace(result, GDEXTENSION_VARIANT_TYPE_BOOL, &b); return true; }
            case 3: case 10: {
                if (size - at < 8) return ok = false;
                uint64_t bits = 0;
                for (unsigned i = 0; i < 8; ++i) bits |= static_cast<uint64_t>(data[at++]) << (i * 8);
                if (tag == 3) { int64_t n; std::memcpy(&n, &bits, 8); replace(result, GDEXTENSION_VARIANT_TYPE_INT, &n); }
                else {
                    double n; std::memcpy(&n, &bits, 8);
                    if (!std::isfinite(n)) return ok = false;
                    replace(result, GDEXTENSION_VARIANT_TYPE_FLOAT, &n);
                }
                return true;
            }
            case 4: return text(result);
            case 5: {
                uint32_t length = count();
                if (!ok || length > StateWriter::max_items || length > size - at) return ok = false;
                Storage array{}; empty_type[GDEXTENSION_VARIANT_TYPE_ARRAY](&array, nullptr);
                int64_t count_value = length, error = 0; const void *arguments[] = {&count_value};
                array_resize(&array, arguments, &error, 1);
                if (error) ok = false;
                for (uint32_t i = 0; ok && i < length; ++i) read(api.array_write(&array, i), depth + 1);
                if (ok) replace(result, GDEXTENSION_VARIANT_TYPE_ARRAY, &array);
                destroy_type[GDEXTENSION_VARIANT_TYPE_ARRAY](&array); return ok;
            }
            case 8: {
                Storage dictionary{}; empty_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dictionary, nullptr);
                replace(result, GDEXTENSION_VARIANT_TYPE_DICTIONARY, &dictionary);
                destroy_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dictionary); return true;
            }
            case 6: case 7: case 9: return dictionary(result, tag, depth);
            default: return ok = false;
        }
    }
    bool dictionary(GDExtensionVariantPtr result, uint8_t tag, unsigned depth) {
        std::shared_ptr<Keys> keys;
        if (tag == 7) {
            uint32_t id = count();
            if (!ok || id >= schemas.size()) return ok = false;
            keys = schemas[id];
        } else {
            uint32_t length = count();
            if (!ok || !length || length > StateWriter::max_items || length > size - at || (tag == 6 && length > 64) || (tag == 9 && length <= 64)) return ok = false;
            keys = std::make_shared<Keys>(); keys->reserve(length);
            for (uint32_t i = 0; i < length; ++i) {
                Value value; std::string encoded;
                if (!text(value, &encoded) || (i && encoded <= keys->back()->text)) return ok = false;
                keys->push_back(std::make_unique<CachedKey>(value, std::move(encoded)));
            }
            if (tag == 6) schemas.push_back(keys);
        }
        Storage dictionary{}; empty_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dictionary, nullptr);
        for (const auto &key : *keys) if (!read(api.dictionary_write(&dictionary, &key->value), depth + 1)) break;
        if (ok) replace(result, GDEXTENSION_VARIANT_TYPE_DICTIONARY, &dictionary);
        destroy_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dictionary); return ok;
    }
};

void state_unpack(GDExtensionConstVariantPtr value, GDExtensionVariantPtr result) {
    size_t length = static_cast<size_t>(count_of(value));
    if (length < 5 || length > StateWriter::max_bytes) { api.nil(result); return; }
    Builtin input(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, value);
    const auto *bytes = api.byte_index_const(&input.storage, 0);
    if (bytes[0] != 65 || bytes[1] != 84 || bytes[2] != 68 || bytes[3] != 1) { api.nil(result); return; }
    Value decoded; StateReader reader(bytes, length);
    if (reader.read(decoded) && reader.at == length && api.type(decoded) == GDEXTENSION_VARIANT_TYPE_DICTIONARY) api.copy(result, decoded);
    else api.nil(result);
}
