-- =======================================================
-- Script: sast.lua
-- Description: Smart Audio & Subtitle Track Selection (SAST) for mpv
-- Author: Boris Zatserkovnyy
-- Version: 1.1.0
-- GitHub: https://github.com/zatserkovnyy/mpv-sast
-- =======================================================

local mp = require("mp")
local utils = require("mp.utils")

-- ======================================
-- CONSTANTS FOR KEYWORD CHECKS
-- ======================================

local COMMENTARY_KEYWORDS = {
	"author",
	"audio description",
	"commentary",
	"description",
	"director",
	"director's commentary",
	"коммент",
	"Коммент",
	"комментарии",
	"Комментарии",
	"описание",
	"Описание",
	"режиссер",
	"Режиссер",
}

local FORCED_EXCLUDE_KEYWORDS = {
	"forc",
	"force",
	"forced",
	"hard",
	"hardsub",
	"hardcoded",
	"sign",
	"signs",
	"надписи",
	"Надписи",
	"принуд",
	"Принуд",
	"форс",
	"Форс",
}

local RUSSIAN_FULL_KEYWORDS = {
	"complete",
	"full",
	"rus",
	"rus ass",
	"rus complete",
	"rus full",
	"rus pgs",
	"rus sdh",
	"rus srt",
	"rus sub",
	"rus subs",
	"russian",
	"russian ass",
	"russian complete",
	"russian full",
	"russian pgs",
	"russian sdh",
	"russian srt",
	"russian sub",
	"russian subs",
	"russian subtitles",
	"rus subtitles",
	"russub",
	"полные",
	"Полные",
	"полный",
	"Полный",
	"рус",
	"Рус",
	"русские субтитры",
	"Русские субтитры",
	"русский sdh",
	"Русский sdh",
	"русский суб",
	"Русский суб",
	"русские полные",
	"Русские полные",
	"руссуб",
	"Руссуб",
}

local RUSSIAN_FORCED_KEYWORDS = {
	"forc",
	"force",
	"forced",
	"forced pgs",
	"forced rus",
	"forced russian",
	"forced subtitles rus",
	"hard",
	"hardsub",
	"hardcoded",
	"rus forced",
	"rus hardcoded",
	"rus signs",
	"russian forced",
	"russian hardcoded",
	"russian signs",
	"sign",
	"signs",
	"signs only",
	"forced rus sub",
	"russian signs only",
	"надписи",
	"Надписи",
	"надписи только",
	"Надписи только",
	"принуд",
	"Принуд",
	"русские надписи",
	"Русские надписи",
	"принудительные русские",
	"Принудительные русские",
	"русские принуд",
	"Русские принуд",
	"форс",
	"Форс",
}

local CODEC_PRIORITY = {
    ["truehd"] = 8,
    ["dts-hd ma"] = 7,
    ["dts-hd-ma"] = 7,
    ["dtshd ma"] = 7,
    ["dtshd-ma"] = 7,
    ["dts-hd"] = 6,
    ["pcm"] = 6,
    ["flac"] = 6,
    ["alac"] = 6,
    ["eac3"] = 5,
    ["dts"] = 4,
    ["ac3"] = 3,
    ["opus"] = 2,
    ["aac"] = 1,
    ["vorbis"] = 1,
    ["mp3"] = 0
}

-- ======================================
-- STATE
-- ======================================

local state = {
    audio_tracks = {},
    sub_tracks = {},
    aid = nil,
    sid = nil
}

local debounce_timer = nil

-- ======================================
-- UTILITIES
-- ======================================

local function get_val(track, prop)
    return (track and track[prop] or ""):lower()
end

local function has_keywords(text, keywords)
    if not text or text == "" then
        return false
    end
    for _, kw in ipairs(keywords) do
        if text:find(kw, 1, true) then
            return true
        end
    end
    return false
end

local function is_lang_ru(lang)
    if not lang or lang == "" then
        return false
    end
    return lang == "ru" or lang == "rus" or lang:match("^ru%-") ~= nil
end

local function is_lang_en(lang)
    if not lang or lang == "" then
        return false
    end
    return lang == "en" or lang == "eng" or lang:match("^en%-") ~= nil
end

-- ======================================
-- TRACK CHECKS
-- ======================================

local function is_excluded_audio(track)
    local l = get_val(track, "lang")
    return l == "uk" or l == "ukr" or l == "ua" or l:match("^uk%-") ~= nil
end

local function is_commentary(track)
    local t = get_val(track, "title")
    return has_keywords(t, COMMENTARY_KEYWORDS) or (t:find("director", 1, true) and t:find("comment", 1, true))
end

local function is_original_audio(track)
    if get_val(track, "title"):find("original", 1, true) then
        return true
    end
    local l = get_val(track, "lang")
    return l == "" or not (is_lang_ru(l) or is_lang_en(l))
end

local function is_english_audio(track)
    return is_lang_en(get_val(track, "lang"))
end
local function is_russian_audio(track)
    return is_lang_ru(get_val(track, "lang"))
end

local function is_full_russian_sub(sub)
    local l, t = get_val(sub, "lang"), get_val(sub, "title")
    if l ~= "" and not is_lang_ru(l) then
        return false
    end
    if has_keywords(t, FORCED_EXCLUDE_KEYWORDS) then
        return false
    end
    return is_lang_ru(l) or has_keywords(t, RUSSIAN_FULL_KEYWORDS)
end

local function is_forced_russian_sub(sub)
    local l, t = get_val(sub, "lang"), get_val(sub, "title")
    return is_lang_ru(l) and (sub.forced or has_keywords(t, RUSSIAN_FORCED_KEYWORDS))
end

local function has_full_russian_subs()
    for _, s in ipairs(state.sub_tracks) do
        if is_full_russian_sub(s) then
            return true
        end
    end
    return false
end

-- ======================================
-- ACTIONS
-- ======================================

local function set_prop(name, id)
    if state[name] ~= id then
        state[name] = id
        mp.set_property(name, id or "no")
    end
end

local function update_cache()
    state.audio_tracks, state.sub_tracks = {}, {}
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == "audio" then
            table.insert(state.audio_tracks, t)
        elseif t.type == "sub" then
            table.insert(state.sub_tracks, t)
        end
    end
end

local function load_external_sub()
    local path = mp.get_property("path")
    if not path or path:find("^%a+://") then
        return
    end

    local dir, filename = utils.split_path(path)
    local name = filename:match("^(.*)%.")
    if not name then
        return
    end

    for _, ext in ipairs({".ass", ".ssa", ".srt", ".vtt"}) do
        local fpath = utils.join_path(dir, name .. ext)
        local f = io.open(fpath, "r")
        if f then
            f:close()
            local _, target = utils.split_path(fpath)
            for _, s in ipairs(state.sub_tracks) do
                if s.external and s["external-filename"] then
                    local _, existing = utils.split_path(s["external-filename"])
                    if existing == target then
                        set_prop("sid", s.id)
                        return
                    end
                end
            end
            mp.commandv("sub-add", fpath, "select")
            return
        end
    end
end

-- ======================================
-- SELECTION LOGIC
-- ======================================

local function get_best_audio()
    if #state.audio_tracks == 0 then
        return mp.get_property_number("aid")
    end

    local p_ru = {function(t)
        return is_original_audio(t) and not is_commentary(t) and not is_excluded_audio(t)
    end, function(t)
        local l = get_val(t, "lang")
        return not (is_lang_ru(l) or is_lang_en(l) or is_excluded_audio(t)) and not is_commentary(t)
    end, function(t)
        return is_english_audio(t) and not is_commentary(t) and not is_excluded_audio(t)
    end}

    local p_no_ru = {function(t)
        return is_russian_audio(t) and not is_commentary(t) and not is_excluded_audio(t)
    end, function(t)
        return is_original_audio(t) and not is_commentary(t) and not is_excluded_audio(t)
    end, function(t)
        return is_english_audio(t) and not is_commentary(t) and not is_excluded_audio(t)
    end, function(t)
        return not is_commentary(t) and not is_excluded_audio(t)
    end}

    local priorities = has_full_russian_subs() and p_ru or p_no_ru
    local candidates = {}

    for _, pred in ipairs(priorities) do
        for _, t in ipairs(state.audio_tracks) do
            if pred(t) then
                table.insert(candidates, t)
            end
        end
        if #candidates > 0 then
            break
        end
    end

    if #candidates == 0 then
        return mp.get_property_number("aid")
    end

    table.sort(candidates, function(a, b)
        local cha, chb = a["audio-channels"] or 0, b["audio-channels"] or 0
        if cha ~= chb then
            return cha > chb
        end

        local sca = CODEC_PRIORITY[get_val(a, "codec")] or 0
        local scb = CODEC_PRIORITY[get_val(b, "codec")] or 0
        if sca ~= scb then
            return sca > scb
        end

        return (a.id or 0) < (b.id or 0)
    end)

    return candidates[1].id
end

local function sync_subs(aid)
    local audio = nil
    for _, t in ipairs(state.audio_tracks) do
        if t.id == aid then
            audio = t
            break
        end
    end

    for _, s in ipairs(state.sub_tracks) do
        if s.external then
            set_prop("sid", s.id)
            return
        end
    end

    if not audio then
        set_prop("sid", nil)
        return
    end

    local matcher = is_russian_audio(audio) and is_forced_russian_sub or is_full_russian_sub
    for _, s in ipairs(state.sub_tracks) do
        if matcher(s) then
            set_prop("sid", s.id)
            return
        end
    end

    set_prop("sid", nil)
end

local function apply_logic()
    update_cache()
    local best_aid = get_best_audio()
    set_prop("aid", best_aid)
    sync_subs(best_aid)
end

-- ======================================
-- EVENTS
-- ======================================

mp.register_event("file-loaded", function()
    if debounce_timer then
        debounce_timer:kill()
    end

    mp.add_timeout(0.05, function()
        state.aid, state.sid = "init", "init"

        update_cache()
        load_external_sub()

        local best_aid = get_best_audio()
        set_prop("aid", best_aid)
        sync_subs(best_aid)
    end)
end)

mp.register_event("tracks-changed", function()
    if debounce_timer then
        debounce_timer:kill()
    end
    debounce_timer = mp.add_timeout(0.1, apply_logic)
end)

mp.observe_property("aid", "number", function(_, aid)
    if aid and aid ~= state.aid then
        state.aid = aid
        sync_subs(aid)
    end
end)
