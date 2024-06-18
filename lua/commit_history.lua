local P = {}
local T = {}
require("tools/metatable")
local reload_env = require("tools/env_api")

local function is_candidate_in_type(cand, excluded_types)
    local cs = cand:get_genuines()
    for _, c in pairs(cs) do
        if table.find_index(excluded_types, c.type) then
            return true
        end
    end
    return false
end

function P.init(env)
    local config = env.engine.schema.config
    env.mem = Memory(env.engine, env.engine.schema)
    env.remove_user_word_key = config:get_string("key_binder/remove_user_word") or "Control+q"
    env.prompt = config:get_string("history" .. "/tips") or "上屏历史"
end

function P.func(key, env)
    local engine = env.engine
    local context = engine.context
    local composition = context.composition
    if composition:empty() then return 2 end
    local segment = composition:back()
    if segment.prompt:match(env.prompt) and (key:repr() == env.remove_user_word_key) then
        local cand = context:get_selected_candidate()
        env.mem:user_lookup(cand.comment, true)
        for entry in env.mem:iter_user() do
            if entry.text == cand.text then
                env.mem:update_userdict(entry, -1, '')
            end
        end
    end
    return 2
end

function P.fini(env)
    if env.mem then
        env.mem:disconnect()
        env.mem = nil
    end
end

function T.init(env)
    reload_env(env)
    env.history_list = {}
    local config = env.engine.schema.config
    env.tag = config:get_string("history" .. "/tag") or "history"
    env.prompt = config:get_string("history" .. "/tips") or "上屏历史"
    env.trigger_prefix = config:get_string("history" .. "/prefix") or "/hs"
    env.initial_quality = config:get_int("history" .. "/initial_quality") or 1000
    local history_num_max = config:get_string("history" .. "/history_num_max") or 30
    local excluded_types = env:Config_get("history" .. "/excluded_types") or {}
    if #env.history_list >= tonumber(history_num_max) then
        table.remove(env.history_list, 1)
    end
    env.notifier_commit_history = env.engine.context.commit_notifier:connect(function(ctx)
        local cand = ctx:get_selected_candidate()
        if cand and not is_candidate_in_type(cand, excluded_types) then
            table.insert(env.history_list, cand)
        end
    end)
end

function T.func(input, seg, env)
    local composition = env.engine.context.composition
    if (composition:empty()) then return end
    if #env.history_list < 1 then return end
    local segment = composition:back()
    if seg:has_tag(env.tag) or (input == env.trigger_prefix) then
        segment.prompt = "〔" .. env.prompt .. "〕"
        local his_cands = env.history_list
        for i = #his_cands, 1, -1 do
            local cand = Candidate("history", seg.start, seg._end, his_cands[i].text, his_cands[i].preedit)
            local cand_uniq = cand:to_uniquified_candidate(cand.type, cand.text, cand.comment:sub(1, 11))
            cand_uniq.quality = env.initial_quality
            yield(cand_uniq)
        end
    end
end

function T.fini(env)
    env.notifier_commit_history:disconnect()
end

return {
    processor = { init = P.init, func = P.func, fini = P.fini },
    translator = { init = T.init, func = T.func, fini = T.fini },
}
