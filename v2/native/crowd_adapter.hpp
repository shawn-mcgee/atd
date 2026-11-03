// Bulk movement-index preparation. Definitions are read afresh each rebuild;
// only immutable name text is cached, so live content edits remain observable.
struct BodyRule { bool mobile; int64_t radius; bool simple; double speed; bool light; bool weapon; };
void prepare_actors(Kernel &kernel, GDExtensionConstVariantPtr actors, GDExtensionConstVariantPtr definitions, GDExtensionConstVariantPtr velocities) {
    Builtin list(GDEXTENSION_VARIANT_TYPE_ARRAY, actors), units(GDEXTENSION_VARIANT_TYPE_DICTIONARY, definitions), previous(GDEXTENSION_VARIANT_TYPE_DICTIONARY, velocities);
    int64_t size = count_of(actors);
    bool has_previous = count_of(velocities) > 0;
    std::vector<int64_t> frame; frame.reserve(static_cast<size_t>(size * 7));
    std::unordered_map<std::string, BodyRule> rules;
    kernel.actors.clear(); kernel.actors.reserve(static_cast<size_t>(size));
    kernel.simple_rules.clear(); kernel.simple_rules.reserve(static_cast<size_t>(size));
    for (int64_t i = 0; i < size; ++i) {
        auto actor = api.array_index(&list.storage, i);
        if (field_integer(actor, HP) <= 0) continue;
        Value name(actor, DEFINITION);
        const auto &text = key_text(kernel, name);
        auto rule = rules.find(text);
        if (rule == rules.end()) {
            GDExtensionBool valid;
            if (!api.has_key(definitions, name, &valid)) continue;
            auto definition = api.dictionary_index(&units.storage, name);
            if (!definition) continue;
            Value caps(definition, CAPS), move(caps, MOVE), radius(definition, COLLISION_RADIUS);
            double amount = 0.2;
            if (api.type(radius) == GDEXTENSION_VARIANT_TYPE_INT) amount = static_cast<double>(integer(radius));
            else if (api.type(radius) == GDEXTENSION_VARIANT_TYPE_FLOAT) api.to(GDEXTENSION_VARIANT_TYPE_FLOAT)(&amount, radius);
            Value source(caps, CHYME_SOURCE), spawner(caps, PASSIVE_SPAWNER), illumination(caps, ILLUMINATION), blocker(caps, LIGHT_BLOCKER), weapon(caps, WEAPON);
            double speed = 0;
            if (move.valid) {
                Value value(move, SPEED);
                if (api.type(value) == GDEXTENSION_VARIANT_TYPE_INT) speed = static_cast<double>(integer(value));
                else if (api.type(value) == GDEXTENSION_VARIANT_TYPE_FLOAT) api.to(GDEXTENSION_VARIANT_TYPE_FLOAT)(&speed, value);
            }
            rule = rules.emplace(text, BodyRule{bool(move.valid), static_cast<int64_t>(std::round(amount * 1024)), !source.valid && !spawner.valid, speed, bool(illumination.valid || blocker.valid), bool(weapon.valid)}).first;
        }
        if (!rule->second.mobile) continue;
        int64_t id = field_integer(actor, ID), owner = field_integer(actor, OWNER);
        Value position(actor, POSITION), velocity(actor, VELOCITY);
        auto point = array_point(position);
        GDExtensionConstVariantPtr old = velocity;
        if (has_previous) {
            Storage key{}; api.from(GDEXTENSION_VARIANT_TYPE_INT)(&key, &id); GDExtensionBool valid;
            if (api.has_key(velocities, &key, &valid)) old = api.dictionary_index(&previous.storage, &key);
            api.destroy(&key);
        }
        if (!old || api.type(old) != GDEXTENSION_VARIANT_TYPE_ARRAY) old = velocity;
        atd::Point delta{};
        if (api.type(old) == GDEXTENSION_VARIANT_TYPE_ARRAY && count_of(old) == 3) delta = array_point(old);
        frame.insert(frame.end(), {id, owner, rule->second.radius, point.q, point.r, delta.q, delta.r});
        kernel.actors.emplace(id, std::make_unique<ActorRef>(actor));
        if (rule->second.simple) kernel.simple_rules.emplace(id, SimpleRule{rule->second.speed, rule->second.light, rule->second.weapon});
    }
    kernel.movement.prepare(frame.data(), frame.size());
}
void begin_tick(Kernel &kernel, GDExtensionConstVariantPtr actors, GDExtensionVariantPtr result) {
    Builtin list(GDEXTENSION_VARIANT_TYPE_ARRAY, actors);
    Storage previous{}; api.constructor(GDEXTENSION_VARIANT_TYPE_DICTIONARY, 0)(&previous, nullptr);
    int64_t size = count_of(actors);
    for (int64_t i = 0; i < size; ++i) {
        auto actor = api.array_index(&list.storage, i);
        Value id(actor, ID), velocity(actor, VELOCITY);
        auto saved = api.dictionary_write(&previous, id); api.destroy(saved);
        if (velocity.valid) api.copy(saved, velocity);
        else point_variant(saved, {});
        set_point(const_cast<void *>(actor), VELOCITY, {});
    }
    api.from(GDEXTENSION_VARIANT_TYPE_DICTIONARY)(result, &previous);
    api.destructor(GDEXTENSION_VARIANT_TYPE_DICTIONARY)(&previous);
}
void body_info(Kernel &kernel, int64_t id, GDExtensionVariantPtr result) {
    auto actor = kernel.actors.find(id); const auto *body = kernel.movement.body(id);
    Storage array{}; api.constructor(GDEXTENSION_VARIANT_TYPE_ARRAY, 0)(&array, nullptr);
    if (actor != kernel.actors.end() && body) {
        int64_t size = 7, error = 0; const void *arguments[] = {&size}; array_resize(&array, arguments, &error, 1);
        int64_t values[] = {body->owner, body->radius, body->q, body->r, body->vq, body->vr};
        for (int i = 0; i < 7; ++i) {
            auto item = api.array_write(&array, i); api.destroy(item);
            if (!i) api.copy(item, &actor->second->value);
            else api.from(GDEXTENSION_VARIANT_TYPE_INT)(item, &values[i - 1]);
        }
    }
    api.from(GDEXTENSION_VARIANT_TYPE_ARRAY)(result, &array); api.destructor(GDEXTENSION_VARIANT_TYPE_ARRAY)(&array);
}
void owner_ids(Kernel &kernel, GDExtensionVariantPtr result) {
    auto owners = kernel.movement.owner_ids();
    Storage array{}; api.constructor(GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY, 0)(&array, nullptr);
    int64_t size = static_cast<int64_t>(owners.size()), error = 0; const void *arguments[] = {&size}; int_resize(&array, arguments, &error, 1);
    if (size && !error) std::memcpy(api.int_index(&array, 0), owners.data(), owners.size() * sizeof(int64_t));
    api.from(GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY)(result, &array); api.destructor(GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY)(&array);
}

void settle_actors(Kernel &kernel, GDExtensionConstVariantPtr actors, GDExtensionConstVariantPtr defeated, int64_t hz, int64_t revision, GDExtensionVariantPtr result) {
    if (!revision || revision != kernel.world.revision) { api.nil(result); return; }
    Builtin list(GDEXTENSION_VARIANT_TYPE_ARRAY, actors);
    int64_t size = count_of(actors), used = 0, error = 0;
    bool has_defeated = count_of(defeated) > 0;
    Storage changed{}; api.constructor(GDEXTENSION_VARIANT_TYPE_ARRAY, 0)(&changed, nullptr);
    const void *arguments[] = {&size}; array_resize(&changed, arguments, &error, 1);
    for (int64_t i = 0; i < size; ++i) {
        auto actor = api.array_index(&list.storage, i); int64_t id = field_integer(actor, ID);
        const auto *body = kernel.movement.body(id);
        if (!body || !kernel.actors.count(id)) continue;
        if (has_defeated) {
            Value owner; int64_t number = body->owner; api.destroy(owner); api.from(GDEXTENSION_VARIANT_TYPE_INT)(owner, &number);
            GDExtensionBool valid; if (api.has_key(defeated, owner, &valid)) continue;
        }
        Value order(actor, ORDER);
        if (count_of(order)) continue;
        if (!kernel.movement.pressure(id, body->q, body->r)) continue;
        Value moved; api.destroy(moved); settle(kernel, actor, hz, moved, true);
        GDExtensionBool did_move; api.to(GDEXTENSION_VARIANT_TYPE_BOOL)(&did_move, moved);
        if (!did_move) continue;
        Value position(actor, POSITION); auto point = array_point(position);
        kernel.movement.moved(id, point.q, point.r); // Subsequent actors see this move.
        auto item = api.array_write(&changed, used++); api.destroy(item); api.copy(item, actor);
    }
    const void *trim[] = {&used}; array_resize(&changed, trim, &error, 1);
    api.from(GDEXTENSION_VARIANT_TYPE_ARRAY)(result, &changed); api.destructor(GDEXTENSION_VARIANT_TYPE_ARRAY)(&changed);
}

// Process a contiguous run of independent point orders and no-op idle actors.
// Stop before general handlers, due automatic targeting or A*, preserving order.
void point_orders(Kernel &kernel, GDExtensionConstVariantPtr actors, int64_t start, GDExtensionConstVariantPtr defeated, int64_t tick, int64_t hz, int64_t revision, bool sync, GDExtensionVariantPtr result) {
    if (!revision || revision != kernel.world.revision) { api.nil(result); return; }
    Builtin list(GDEXTENSION_VARIANT_TYPE_ARRAY, actors);
    int64_t size = count_of(actors), processed = 0, used = 0, capacity = sync ? std::max<int64_t>(0, size - start) : 0, error = 0;
    bool has_defeated = count_of(defeated) > 0, light_dirty = false;
    Storage changed{}; api.constructor(GDEXTENSION_VARIANT_TYPE_ARRAY, 0)(&changed, nullptr);
    const void *arguments[] = {&capacity}; array_resize(&changed, arguments, &error, 1);
    for (int64_t i = std::max<int64_t>(0, start); i < size; ++i) {
        auto actor = api.array_index(&list.storage, i);
        if (field_integer(actor, HP) <= 0) { ++processed; continue; }
        if (has_defeated) {
            Value owner(actor, OWNER); GDExtensionBool valid;
            if (api.has_key(defeated, owner, &valid)) { ++processed; continue; }
        }
        int64_t id = field_integer(actor, ID); auto rule = kernel.simple_rules.find(id);
        if (rule == kernel.simple_rules.end()) break;
        Value construction(actor, CONSTRUCTION), production(actor, PRODUCTION), order(actor, ORDER);
        if (count_of(construction) || count_of(production)) break;
        if (rule->second.weapon && tick % 10 == 0 && !field_bool(order, MANUAL)) break;
        if (!count_of(order)) { ++processed; continue; }
        Value kind(order, KIND);
        if (!kind.valid || key_text(kernel, kind) != "move") break;
        if (field_integer(order, START_TICK) > tick) { ++processed; continue; }
        Value destination(order, POINT);
        auto goal = array_point(destination);
        int64_t speed = std::max<int64_t>(1, static_cast<int64_t>(std::round(rule->second.speed * 1024 / hz)));
        int64_t moved = point_move(kernel, actor, goal, speed, tick, hz, revision);
        if (moved < 0) break;
        ++processed;
        if (!moved) continue;
        Value position(actor, POSITION); auto point = array_point(position);
        kernel.movement.moved(id, point.q, point.r);
        light_dirty = light_dirty || rule->second.light;
        if (sync) { auto item = api.array_write(&changed, used++); api.destroy(item); api.copy(item, actor); }
    }
    const void *trim[] = {&used}; array_resize(&changed, trim, &error, 1);
    Storage dictionary{}; api.constructor(GDEXTENSION_VARIANT_TYPE_DICTIONARY, 0)(&dictionary, nullptr);
    api.from(GDEXTENSION_VARIANT_TYPE_DICTIONARY)(result, &dictionary); api.destructor(GDEXTENSION_VARIANT_TYPE_DICTIONARY)(&dictionary);
    set_integer(result, BATCH_COUNT, processed); set_bool(result, LIGHT_DIRTY, light_dirty);
    Storage changed_value{}; api.from(GDEXTENSION_VARIANT_TYPE_ARRAY)(&changed_value, &changed);
    GDExtensionBool valid; api.set_named(result, &field_names[BATCH_CHANGED], &changed_value, &valid);
    api.destroy(&changed_value); api.destructor(GDEXTENSION_VARIANT_TYPE_ARRAY)(&changed);
}
