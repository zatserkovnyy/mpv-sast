-- =======================================================
-- Script: sast.lua
-- Description: Smart Audio & Subtitle Track Selection (SAST) for mpv
-- Author: Boris Zatserkovnyy
-- Version: 1.0.1
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
	["mp3"] = 0,
}

-- ======================================
-- STATE
-- ======================================

local state = {
	audio_track_list = {},
	subtitle_track_list = {},
	current_audio_id = nil,
	current_sub_id = nil,
}

local track_update_timer = nil

-- ======================================
-- HELPER: KEYWORD CHECK
-- ======================================

local function text_contains_keywords(text, keywords)
	if not text or text == "" then
		return false
	end
	text = text:lower()
	for _, kw in ipairs(keywords) do
		if text:find(kw, 1, true) then
			return true
		end
	end
	return false
end

-- ======================================
-- HELPER: TRACK TYPE CHECKS
-- ======================================

local function is_original_audio(track)
	if not track then
		return false
	end

	local title = (track.title or ""):lower()
	if title:find("original", 1, true) then
		return true
	end

	local lang = (track.lang or ""):lower()
	return lang == "" or not (lang == "ru" or lang == "rus" or lang == "en" or lang == "eng")
end

local function is_english_audio(track)
	if not track then
		return false
	end
	local lang = (track.lang or ""):lower()
	return lang == "en" or lang == "eng"
end

local function is_russian_audio(track)
	if not track then
		return false
	end
	local lang = (track.lang or ""):lower()
	return lang == "ru" or lang == "rus"
end

local function is_excluded_audio(track)
    return false
end

local function is_commentary(track)
	if not track then
		return false
	end
	local title = (track.title or ""):lower()
	if text_contains_keywords(title, COMMENTARY_KEYWORDS) then
		return true
	end
	if title:find("director", 1, true) and title:find("comment", 1, true) then
		return true
	end
	return false
end

-- ======================================
-- SUBTITLE CHECKS
-- ======================================

local function is_full_russian_sub(sub)
	if not sub then
		return false
	end

	local lang = (sub.lang or ""):lower()
	local title = (sub.title or ""):lower()

	if lang ~= "" and not (lang == "ru" or lang == "rus") then
		return false
	end

	if text_contains_keywords(title, FORCED_EXCLUDE_KEYWORDS) then
		return false
	end

	local is_ru_lang = (lang == "ru" or lang == "rus")
	if is_ru_lang then
		return true
	end

	local is_ru_title = text_contains_keywords(title, RUSSIAN_FULL_KEYWORDS)
	if is_ru_title then
		return true
	end
	return false
end

local function is_forced_russian_sub(sub)
	if not sub then
		return false
	end
	local lang = (sub.lang or ""):lower()
	local title = (sub.title or ""):lower()
	local is_ru_lang = (lang == "ru" or lang == "rus")
	local is_forced = sub.forced == true or text_contains_keywords(title, RUSSIAN_FORCED_KEYWORDS)
	return is_ru_lang and is_forced
end

-- ======================================
-- SUBTITLE HELPERS
-- ======================================

local function has_full_russian_subs()
	for _, s in ipairs(state.subtitle_track_list) do
		if is_full_russian_sub(s) then
			return true
		end
	end
	return false
end

-- ======================================
-- HELPER: SET PROPERTIES
-- ======================================

local function set_sub_if_needed(sid)
	if state.current_sub_id ~= sid then
		mp.set_property("sid", sid or "no")
		state.current_sub_id = sid
	end
end

local function set_audio_if_needed(aid)
	if state.current_audio_id ~= aid then
		mp.set_property("aid", aid)
		state.current_audio_id = aid
	end
end

-- ======================================
-- CACHE UPDATE
-- ======================================

local function update_track_cache()
	local tracks = mp.get_property_native("track-list") or {}
	state.audio_track_list = {}
	state.subtitle_track_list = {}

	for _, t in ipairs(tracks) do
		if t.type == "audio" then
			table.insert(state.audio_track_list, t)
		elseif t.type == "sub" then
			table.insert(state.subtitle_track_list, t)
		end
	end
end

-- ======================================
-- EXTERNAL SUBTITLE LOADING
-- ======================================

local function get_external_sub_path()
	local path = mp.get_property("path")
	if not path or path:find("^%a+://") then
		return nil
	end

	local dir, filename = utils.split_path(path)
	local name_no_ext = filename:match("^(.*)%.")
	if not name_no_ext then
		return nil
	end

	for _, ext in ipairs({ ".ass", ".ssa", ".srt", ".vtt" }) do
		local full_path = utils.join_path(dir, name_no_ext .. ext)
		local f = io.open(full_path, "r")
		if f then
			f:close()
			return full_path
		end
	end
	return nil
end

local function load_external_subtitle_if_available()
	local ext_path = get_external_sub_path()
	if not ext_path then
		return false
	end

	local _, target_name = utils.split_path(ext_path)

	for _, s in ipairs(state.subtitle_track_list) do
		if s.external and s["external-filename"] then
			local _, existing_name = utils.split_path(s["external-filename"])
			if existing_name == target_name then
				set_sub_if_needed(s.id)
				return true
			end
		end
	end

	mp.commandv("sub-add", ext_path, "select")
	return true
end

-- ======================================
-- SELECT BEST AUDIO
-- ======================================

local function choose_best_audio_track()
	local audio_track_list = state.audio_track_list
	if #audio_track_list == 0 then
		return mp.get_property_number("aid")
	end

	local candidates = {}
	local ru_subs = has_full_russian_subs()

	local priorities = ru_subs
			and {
				function(t)
					return is_original_audio(t) and not is_commentary(t) and not is_excluded_audio(t)
				end,
				function(t)
					local lang = (t.lang or ""):lower()
					return not (lang == "ru" or lang == "rus" or lang == "en" or lang == "eng")
						and not is_commentary(t)
						and not is_excluded_audio(t)
				end,
				function(t)
					return is_english_audio(t) and not is_commentary(t) and not is_excluded_audio(t)
				end,
			}
		or {
			function(t)
				return is_russian_audio(t) and not is_commentary(t) and not is_excluded_audio(t)
			end,
			function(t)
				return is_original_audio(t) and not is_commentary(t) and not is_excluded_audio(t)
			end,
			function(t)
				return is_english_audio(t) and not is_commentary(t) and not is_excluded_audio(t)
			end,
			function(t)
				return not is_commentary(t) and not is_excluded_audio(t)
			end,
		}

	for _, pred in ipairs(priorities) do
		candidates = {}
		for _, t in ipairs(audio_track_list) do
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

	local max_channels = -1
	local best = {}

	for _, t in ipairs(candidates) do
		local ch = t["audio-channels"] or 0
		if ch > max_channels then
			max_channels = ch
			best = { t }
		elseif ch == max_channels then
			table.insert(best, t)
		end
	end

	if #best > 1 then
		local best_track = best[1]
		local best_score = CODEC_PRIORITY[(best_track.codec or ""):lower()] or 0

		for _, t in ipairs(best) do
			local score = CODEC_PRIORITY[(t.codec or ""):lower()] or 0
			if score > best_score then
				best_score = score
				best_track = t
			end
		end

		return best_track.id
	end

	return best[1].id
end

-- ======================================
-- UPDATE SUBTITLES BASED ON AUDIO
-- ======================================

local function sync_subtitles_with_audio(aid)
	local audio_track = nil
	for _, t in ipairs(state.audio_track_list) do
		if t.id == aid then
			audio_track = t
			break
		end
	end

	for _, s in ipairs(state.subtitle_track_list) do
		if s.external then
			set_sub_if_needed(s.id)
			return
		end
	end

	if not audio_track then
		set_sub_if_needed(nil)
		return
	end

	local prefer_forced = is_russian_audio(audio_track)
	local matcher = prefer_forced and is_forced_russian_sub or is_full_russian_sub

	for _, s in ipairs(state.subtitle_track_list) do
		if matcher(s) then
			set_sub_if_needed(s.id)
			return
		end
	end

	set_sub_if_needed(nil)
end

-- ======================================
-- RESET
-- ======================================

local function reset_state()
	state.audio_track_list = {}
	state.subtitle_track_list = {}
	state.current_audio_id = nil
	state.current_sub_id = nil
end

-- ======================================
-- EVENTS
-- ======================================

mp.register_event("file-loaded", function()
	if track_update_timer then
		track_update_timer:kill()
	end
	track_update_timer = mp.add_timeout(0.1, function()
		reset_state()
		update_track_cache()
		load_external_subtitle_if_available()

		local best_aid = choose_best_audio_track()
		set_audio_if_needed(best_aid)

		sync_subtitles_with_audio(best_aid)
	end)
end)

mp.register_event("tracks-changed", function()
	if track_update_timer then
		track_update_timer:kill()
	end
	track_update_timer = mp.add_timeout(0.1, function()
		update_track_cache()

		local best_aid = choose_best_audio_track()
		set_audio_if_needed(best_aid)

		sync_subtitles_with_audio(best_aid)
	end)
end)

mp.observe_property("aid", "number", function(_, aid)
	if aid and aid ~= state.current_audio_id then
		state.current_audio_id = aid
		sync_subtitles_with_audio(aid)
	end
end)
