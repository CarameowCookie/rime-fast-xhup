local reload_env = require("tools/env_api")

local flypy_switcher = {}
local processor = {}
local translator = {}

function flypy_switcher.init(env)
    reload_env(env)
    local config = env.engine.schema.config
    env.page_size = config:get_int("menu/page_size") or 7
    env.comment_hints = config:get_int("translator/spelling_hints") or 1
    env.word_auto_commit_enabled = config:get_bool("flypy_phrase/auto_commit") or false
    env.cn_comment_overwrited = config:get_bool("radical_reverse_lookup/overwrite_comment") or false
    env.en_comment_overwrited = config:get_bool("ecdict_reverse_lookup/overwrite_comment") or false
    env.switch_comment_key = config:get_string("key_binder/switch_comment") or "Control+n"
    env.commit_comment_key = config:get_string("key_binder/commit_comment") or "Control+p"
    env.switch_english_key = config:get_string("key_binder/switch_english") or "Control+g"
    env.easy_en_prefix = config:get_string("recognizer/patterns/easy_en"):match("%^([a-z/]+).*") or "/oe"
    env.switch_options = config:get_string("recognizer/patterns/switch_options"):match("%^([a-z/]+).*") or "/so"
    env.cand_select_kyes = {
        ["space"] = -1,
        ["Return"] = -1,
        ["1"] = 0,
        ["2"] = 1,
        ["3"] = 2,
        ["4"] = 3,
        ["5"] = 4,
        ["6"] = 5,
        ["7"] = 6,
        ["8"] = 7,
        ["9"] = 8,
    }
end

function processor.func(key, env)
    local engine = env.engine
    local schema = engine.schema
    local page_size = schema.page_size
    local context = engine.context
    local config = schema.config
    local composition = context.composition
    if (composition:empty()) then return end
    local segment = composition:back()
    local preedit_code = context:get_script_text():gsub(" ", "")

    if context:has_menu() and (key:repr() == env.switch_comment_key) then
        if preedit_code:match("^" .. env.easy_en_prefix) and env.en_comment_overwrited then
            config:set_bool("ecdict_reverse_lookup/overwrite_comment", false) -- 重写英文注释为空
        elseif preedit_code:match("^" .. env.easy_en_prefix) and (not env.en_comment_overwrited) then
            config:set_bool("ecdict_reverse_lookup/overwrite_comment", true)  -- 重写英文注释为中文
        elseif (not env.cn_comment_overwrited) and (env.comment_hints > 0) then
            config:set_bool("radical_reverse_lookup/overwrite_comment", true) -- 重写注释为注音
        elseif env.cn_comment_overwrited and (env.comment_hints > 0) then
            config:set_int("translator/spelling_hints", 0)
            config:set_bool("radical_reverse_lookup/overwrite_comment", false) -- 重写注释为空
            env:Config_set('radical_reverse_lookup/comment_format/@last', "xform/^.+$//")
        else
            config:set_int("translator/spelling_hints", 1) -- 重写注释为小鹤形码
            config:set_bool("radical_reverse_lookup/overwrite_comment", false)
            env:Config_set('radical_reverse_lookup/comment_format/@last', "xform/^/~/")
        end
        engine:apply_schema(Schema(schema.schema_id))
        context:push_input(preedit_code)
        context:refresh_non_confirmed_composition() -- 刷新当前输入法候选菜单, 实现看到实时效果
        return 1                                    -- kAccept
    end

    if context:has_menu() and (key:repr() == env.commit_comment_key) then
        local cand = context:get_selected_candidate()
        local cand_comment = cand.comment:gsub("%p", "")
        engine:commit_text(cand_comment)
        context:clear()
        return 1
    end

    if (key:repr() == env.switch_english_key) and (schema.schema_id ~= "easy_en") then
        --[[
        context:clear()
        context:push_input(env.easy_en_prefix .. preedit_code)
        context:refresh_non_confirmed_composition() -- 刷新当前输入法候选菜单, 实现看到实时效果
        return 1                                    -- kAccept
    elseif context:has_menu() and (key:repr() == env.switch_easy_en_key) then
    --]]
        context:clear()
        env.engine:apply_schema(Schema("easy_en"))
        context:push_input(preedit_code)
        context:refresh_non_confirmed_composition() -- 刷新当前输入法候选菜单, 实现看到实时效果
        return 1                                    -- kAccept
    end

    if segment.prompt:match("切换配置选项") and (env.cand_select_kyes[key:repr()]) then
        local key_value = env.cand_select_kyes[key:repr()]
        local index = segment.selected_index
        local idx = (key_value == -1) and index or key_value
        -- local page_pos = (index // page_size) + 1
        -- idx = ((key_value == -1) and (page_pos > 1)) and index
        -- idx = ((key_value ~= -1) and (page_pos > 1)) and (key_value + (page_pos - 1) * page_size)
        local selected_cand = segment:get_candidate_at(idx)
        local cand_text = selected_cand.text:gsub(" ", "")

        if (cand_text == "切换纵横布局样式") then
            local menu_style_horizontal = config:get_bool("style/horizontal") or false
            local switch_to_val = not menu_style_horizontal
            config:set_bool("style/horizontal", switch_to_val) -- 重写stytle
        elseif (cand_text == "切换候选序号样式") then
            -- config:set_int("menu/alternative_select_keys", 1234567890)
            local label_style
            if env:Config_get("menu/alternative_select_labels")[1] == 1 then
                label_style = { '①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨', '⓪' }
            else
                label_style = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 0 }
            end
            env:Config_set("menu/alternative_select_labels", label_style)
        elseif (cand_text == "切换Emoji😂显隐") then
            local emoji_visible = env:Config_get("switches/@4/reset")
            local switch_to_val = (emoji_visible > 0) and 0 or 1
            env:Config_set("switches/@4/reset", switch_to_val)
        elseif (cand_text == "切换简体繁体显示") then
            local simp_tran_state = env:Config_get("switches/@3/reset")
            local switch_to_val = (simp_tran_state > 0) and 0 or 1
            env:Config_set("switches/@3/reset", switch_to_val)
        elseif (cand_text == "增加单页候选项数") then
            config:set_int("menu/page_size", (env.page_size + 1))
        elseif (cand_text == "减少单页候选项数") then
            config:set_int("menu/page_size", (env.page_size - 1))
        elseif (cand_text == "开关短语自动上屏") then
            config:set_bool("flypy_phrase/auto_commit", (not env.word_auto_commit_enabled))
        elseif (cand_text == "恢复分号自动上屏") then
            env:Config_set("punctuator/half_shape/;", "；")
        elseif (cand_text == "开关字符码区提示") then
            local charset_hint = env:Config_get("switches/@last/reset")
            local switch_to_val = (charset_hint > 0) and 0 or 1
            env:Config_set("switches/@last/reset", switch_to_val)
        end
        engine:apply_schema(Schema(schema.schema_id))
        return 1 -- kAccept
    end
    return 2     -- kNoop, 不做任何操作, 交给下个组件处理
end

function translator.func(input, seg, env)
    local composition = env.engine.context.composition
    if (composition:empty()) then return end
    local segment = composition:back()
    local trigger_prefix = env.switch_options or "/so"
    if seg:has_tag("switch_options") or (input == trigger_prefix) then
        segment.prompt = "〔" .. "切换配置选项" .. "〕"
        yield(Candidate("switch_options", seg.start, seg._end, "切换纵横布局样式", ""))
        yield(Candidate("switch_options", seg.start, seg._end, "切换候选序号样式", ""))
        yield(Candidate("switch_options", seg.start, seg._end, "切换Emoji😂显隐", ""))
        yield(Candidate("switch_options", seg.start, seg._end, "切换简体繁体显示", ""))
        yield(Candidate("switch_options", seg.start, seg._end, "增加单页候选项数", ""))
        yield(Candidate("switch_options", seg.start, seg._end, "减少单页候选项数", ""))
        -- yield(Candidate("switch_options", seg.start, seg._end, "恢复常规候选按键", ""))
        yield(Candidate("switch_options", seg.start, seg._end, "恢复分号自动上屏", ""))
        yield(Candidate("switch_options", seg.start, seg._end, "开关短语自动上屏", ""))
        yield(Candidate("switch_options", seg.start, seg._end, "开关字符码区提示", ""))
    end
end

return {
    processor = { init = flypy_switcher.init, func = processor.func },
    translator = { init = flypy_switcher.init, func = translator.func },
}
