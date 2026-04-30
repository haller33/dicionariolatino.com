#!/usr/bin/env lua
-- latin.lua – Latin dictionary searcher (with trigram similarity)

local luasql = require("luasql.sqlite3")

-- ----------------------------------------------------------------------
-- Config
-- ----------------------------------------------------------------------
local DB_PATH = "latin_portuguese.db"
local MAX_RESULTS = 20

local BAD_CONTENT_HASH = "32aaccb0c4597738cc2fca23b28557802587b9a9fa91d5c8c54beae8aedee5d9"
local exclude_bad = false

-- ----------------------------------------------------------------------
-- Helper: escape SQL string
-- ----------------------------------------------------------------------
local function escape(s)
    if not s then return "" end
    return s:gsub("'", "''")
end

-- ----------------------------------------------------------------------
-- Helper: add exclusion condition to WHERE clause
-- ----------------------------------------------------------------------
local function add_exclusion(where_clause)
    if exclude_bad then
        if where_clause and where_clause ~= "" then
            return where_clause .. " AND content_hash != '" .. BAD_CONTENT_HASH .. "'"
        else
            return "content_hash != '" .. BAD_CONTENT_HASH .. "'"
        end
    else
        return where_clause or ""
    end
end

-- ----------------------------------------------------------------------
-- Database connection helpers
-- ----------------------------------------------------------------------
local env, conn
local function open_db()
    env = luasql.sqlite3()
    conn = env:connect(DB_PATH)
    if not conn then
        error("Cannot open database '" .. DB_PATH .. "'")
    end
end

local function close_db()
    if conn then conn:close() end
    if env then env:close() end
end

-- ----------------------------------------------------------------------
-- Fuzzy matching (Levenshtein distance) – unchanged
-- ----------------------------------------------------------------------
local function levenshtein(s, t)
    local m, n = #s, #t
    if m == 0 then return n end
    if n == 0 then return m end
    local d = {}
    for i = 0, m do d[i] = { [0] = i } end
    for j = 0, n do d[0][j] = j end
    for i = 1, m do
        local si = s:sub(i, i)
        for j = 1, n do
            local cost = (si == t:sub(j, j)) and 0 or 1
            d[i][j] = math.min(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + cost)
        end
    end
    return d[m][n]
end

local function fuzzy_score(word, target)
    local dist = levenshtein(word:lower(), target:lower())
    local max_len = math.max(#word, #target)
    if max_len == 0 then return 1 end
    return dist / max_len
end

local function fuzzy_search(input, max_results)
    local results = {}
    local cursor = conn:execute("SELECT word, definition, content_hash FROM dictionary")
    local row = cursor:fetch({}, "a")
    while row do
        if not (exclude_bad and row.content_hash == BAD_CONTENT_HASH) then
            local score_word = fuzzy_score(row.word, input)
            local score_def  = fuzzy_score(row.definition or "", input)
            local best = math.min(score_word, score_def)
            if best < 0.45 then
                table.insert(results, { word = row.word, def = row.definition, score = best })
            end
        end
        row = cursor:fetch({}, "a")
    end
    cursor:close()
    table.sort(results, function(a,b) return a.score < b.score end)
    if #results > max_results then
        for i = max_results + 1, #results do results[i] = nil end
    end
    return results
end

-- ----------------------------------------------------------------------
-- Trigram similarity (conservative, no DB changes)
-- ----------------------------------------------------------------------
local trigram_cache = {}   -- word -> table of trigrams (keys = trigram, value = true)

-- Generate trigrams for a word (pad with $ at both ends)
local function get_trigrams(word)
    if trigram_cache[word] then
        return trigram_cache[word]
    end
    local trigrams = {}
    local padded = "$" .. word .. "$"
    for i = 1, #padded - 2 do
        local tri = padded:sub(i, i+2)
        trigrams[tri] = true
    end
    trigram_cache[word] = trigrams
    return trigrams
end

-- Jaccard similarity = |A ∩ B| / |A ∪ B|
local function jaccard_similarity(set1, set2)
    local intersection = 0
    local union = 0
    -- count intersection by checking keys in set1 that exist in set2
    for k, _ in pairs(set1) do
        if set2[k] then
            intersection = intersection + 1
        end
    end
    -- union size = size(set1) + size(set2) - intersection
    local size1 = 0
    for _ in pairs(set1) do size1 = size1 + 1 end
    local size2 = 0
    for _ in pairs(set2) do size2 = size2 + 1 end
    union = size1 + size2 - intersection
    if union == 0 then return 0 end
    return intersection / union
end

local function trigram_search(input, max_results)
    local results = {}
    local query_trigrams = get_trigrams(input:lower())
    local cursor = conn:execute("SELECT word, definition, content_hash FROM dictionary")
    local row = cursor:fetch({}, "a")
    while row do
        if not (exclude_bad and row.content_hash == BAD_CONTENT_HASH) then
            local word_trigrams = get_trigrams(row.word:lower())
            local sim = jaccard_similarity(query_trigrams, word_trigrams)
            if sim > 0.2 then   -- threshold, can be tweaked
                table.insert(results, { word = row.word, def = row.definition, score = sim })
            end
        end
        row = cursor:fetch({}, "a")
    end
    cursor:close()
    table.sort(results, function(a,b) return a.score > b.score end)  -- higher Jaccard = better
    if #results > max_results then
        for i = max_results + 1, #results do results[i] = nil end
    end
    return results
end

-- ----------------------------------------------------------------------
-- Output helpers (colours)
-- ----------------------------------------------------------------------
local function stdout_is_tty()
    local ok, f = pcall(io.open, "/dev/stdout", "r")
    if ok and f then f:close() return true end
    return false
end

local colours = stdout_is_tty() and {
    bold   = "\27[1m",
    green  = "\27[32m",
    yellow = "\27[33m",
    cyan   = "\27[36m",
    reset  = "\27[0m"
} or {
    bold = "", green = "", yellow = "", cyan = "", reset = ""
}

local function print_header(title)
    print(colours.bold .. colours.green .. title .. colours.reset)
end

local function print_result(word, definition)
    io.write(colours.cyan .. word .. colours.reset, ": ")
    if definition and #definition > 0 then
        print(definition:gsub("\n", " "))
    else
        print("(no definition)")
    end
end

-- ----------------------------------------------------------------------
-- Database query functions (unchanged except adding trigram calls where needed)
-- ----------------------------------------------------------------------
local function prefix_search(prefix)
    print_header("Words starting with '" .. prefix .. "':")
    local count = 0
    local where = "word LIKE '" .. escape(prefix) .. "%'"
    where = add_exclusion(where)
    local sql = string.format("SELECT word FROM dictionary WHERE %s LIMIT %d", where, MAX_RESULTS)
    local cursor = conn:execute(sql)
    local row = cursor:fetch({}, "a")
    while row do
        print(" • " .. row.word)
        count = count + 1
        row = cursor:fetch({}, "a")
    end
    cursor:close()
    if count == 0 then print("(none)") end
end

local function definition_search(text)
    print_header("Definitions containing '" .. text .. "':")
    local count = 0
    local where = "definition LIKE '%" .. escape(text) .. "%'"
    where = add_exclusion(where)
    local sql = string.format("SELECT word, definition FROM dictionary WHERE %s LIMIT %d", where, MAX_RESULTS)
    local cursor = conn:execute(sql)
    local row = cursor:fetch({}, "a")
    while row do
        print_result(row.word, row.definition)
        count = count + 1
        row = cursor:fetch({}, "a")
    end
    cursor:close()
    if count == 0 then print("(none)") end
end

local function exact_search(query)
    print_header("Exact match for '" .. query .. "':")
    local where = "word = '" .. escape(query) .. "'"
    where = add_exclusion(where)
    local sql = "SELECT word, definition FROM dictionary WHERE " .. where
    local cursor = conn:execute(sql)
    local row = cursor:fetch({}, "a")
    if row then
        print_result(row.word, row.definition)
    else
        print("Not found.")
    end
    cursor:close()
end

local function fuzzy_and_prefix_wrapper(query, no_fuzzy)
    local prefix_list = {}
    local where = "word LIKE '" .. escape(query) .. "%'"
    where = add_exclusion(where)
    local sql = string.format("SELECT word FROM dictionary WHERE %s LIMIT %d", where, MAX_RESULTS)
    local cursor = conn:execute(sql)
    local row = cursor:fetch({}, "a")
    while row do
        table.insert(prefix_list, row.word)
        row = cursor:fetch({}, "a")
    end
    cursor:close()

    if #prefix_list > 0 then
        print_header("Prefix matches for '" .. query .. "':")
        for _, w in ipairs(prefix_list) do print(" • " .. w) end
        print()
    end

    if not no_fuzzy then
        local fuzzy_list = fuzzy_search(query, MAX_RESULTS)
        if #fuzzy_list > 0 then
            print_header("Fuzzy matches for '" .. query .. "':")
            for _, r in ipairs(fuzzy_list) do
                print_result(r.word, r.def)
            end
        elseif #prefix_list == 0 then
            print("Nothing found.")
        end
    elseif #prefix_list == 0 then
        print("Nothing found.")
    end
end

-- ----------------------------------------------------------------------
-- Raw HTML output
-- ----------------------------------------------------------------------
local function get_raw_html(word)
    local where = "word = '" .. escape(word) .. "'"
    where = add_exclusion(where)
    local sql = "SELECT raw_html FROM dictionary WHERE " .. where
    local cursor = conn:execute(sql)
    local row = cursor:fetch({}, "a")
    cursor:close()
    if row and row.raw_html then
        print(row.raw_html)
    else
        io.stderr:write("No HTML content found for word: " .. word .. "\n")
        os.exit(1)
    end
end

local function handle_html(word)
    get_raw_html(word)
end

-- ----------------------------------------------------------------------
-- REPL (added trigram command)
-- ----------------------------------------------------------------------
local function repl()
    print()
    print_header("Latin Dictionary REPL (luasql.sqlite3)")
    print("Current result limit: " .. MAX_RESULTS)
    print("Exclude bad content_hash: " .. tostring(exclude_bad))
    print("Commands:")
    print("  ?           – show this help")
    print("  q           – quit")
    print("  limit N     – set max results to N (e.g. limit 5)")
    print("  bad         – toggle exclusion of the known bad content_hash")
    print("  p:WORD      – prefix search (word completion)")
    print("  f:WORD      – fuzzy search (typo‑tolerant, Levenshtein)")
    print("  t:WORD      – trigram similarity search (Jaccard index)")
    print("  d:TEXT      – search inside definitions")
    print("  h:WORD      – output raw HTML (for piping to your dumper)")
    print("  WORD        – exact + prefix + fuzzy (combined)")
    print()
    io.write(colours.green .. "> " .. colours.reset)
    io.flush()

    for line in io.lines() do
        line = line:match("^%s*(.-)%s*$")
        if line == "" then
            -- skip
        elseif line == "q" or line == "quit" or line == "exit" then
            break
        elseif line == "?" then
            print("Commands: ?, q, limit N, bad, p:WORD, f:WORD, t:WORD, d:TEXT, h:WORD, WORD")
        elseif line:sub(1,5) == "limit" then
            local n = tonumber(line:match("limit%s+(%d+)"))
            if n and n > 0 then
                MAX_RESULTS = n
                print("Result limit set to " .. MAX_RESULTS)
            else
                print("Invalid limit. Use: limit N (positive integer)")
            end
        elseif line == "bad" then
            exclude_bad = not exclude_bad
            print("Exclude bad content_hash: " .. tostring(exclude_bad))
        elseif line:sub(1,2) == "p:" then
            prefix_search(line:sub(3))
        elseif line:sub(1,2) == "f:" then
            local fuzzy_results = fuzzy_search(line:sub(3), MAX_RESULTS)
            print_header("Fuzzy matches for '" .. line:sub(3) .. "':")
            for _, r in ipairs(fuzzy_results) do
                print_result(r.word, r.def)
            end
            if #fuzzy_results == 0 then print("(none)") end
        elseif line:sub(1,2) == "t:" then
            local trigram_results = trigram_search(line:sub(3), MAX_RESULTS)
            print_header("Trigram matches for '" .. line:sub(3) .. "':")
            for _, r in ipairs(trigram_results) do
                print_result(r.word, r.def)
            end
            if #trigram_results == 0 then print("(none)") end
        elseif line:sub(1,2) == "d:" then
            definition_search(line:sub(3))
        elseif line:sub(1,2) == "h:" then
            handle_html(line:sub(3))
        else
            fuzzy_and_prefix_wrapper(line, false)
        end
        print()
        io.write(colours.green .. "> " .. colours.reset)
        io.flush()
    end
end

-- ----------------------------------------------------------------------
-- Parse command line (added --trigram)
-- ----------------------------------------------------------------------
local function show_usage()
    print([[
Usage:
  lua latin.lua                      → interactive REPL
  lua latin.lua --limit N "word"     → set limit to N for that search
  lua latin.lua "word"               → exact + prefix + fuzzy (default)
  lua latin.lua --exact "word"       → only exact match
  lua latin.lua --no-fuzzy "word"    → exact + prefix (no fuzzy)
  lua latin.lua --prefix "pref"      → list words starting with 'pref'
  lua latin.lua --fuzzy "word"       → fuzzy search only (Levenshtein)
  lua latin.lua --trigram "word"     → trigram similarity search (Jaccard)
  lua latin.lua --def "text"         → search inside definitions
  lua latin.lua --html "word"        → output raw HTML for that word
  lua latin.lua --exclude-bad        → exclude entries with the problematic content_hash
]])
end

local function main(args)
    open_db()
    local cursor = conn:execute("SELECT name FROM sqlite_master WHERE type='table' AND name='dictionary'")
    local row = cursor:fetch({}, "a")
    cursor:close()
    if not row then
        print("Error: 'dictionary' table not found.")
        close_db()
        os.exit(1)
    end

    local limit = MAX_RESULTS
    local no_fuzzy = false
    local exact_mode = false
    local new_args = {}
    local i = 1
    while i <= #args do
        if args[i] == "--limit" and i+1 <= #args then
            local n = tonumber(args[i+1])
            if n and n >= 0 then
                limit = n
            else
                print("Invalid --limit value. Using default " .. MAX_RESULTS)
            end
            i = i + 2
        elseif args[i] == "--no-fuzzy" then
            no_fuzzy = true
            i = i + 1
        elseif args[i] == "--exact" then
            exact_mode = true
            i = i + 1
        elseif args[i] == "--exclude-bad" then
            exclude_bad = true
            i = i + 1
        else
            table.insert(new_args, args[i])
            i = i + 1
        end
    end
    MAX_RESULTS = limit

    if #new_args == 0 then
        repl()
    elseif new_args[1] == "--prefix" and #new_args >= 2 then
        prefix_search(new_args[2])
    elseif new_args[1] == "--fuzzy" and #new_args >= 2 then
        local fuzzy_results = fuzzy_search(new_args[2], MAX_RESULTS)
        print_header("Fuzzy matches for '" .. new_args[2] .. "':")
        for _, r in ipairs(fuzzy_results) do
            print_result(r.word, r.def)
        end
        if #fuzzy_results == 0 then print("(none)") end
    elseif new_args[1] == "--trigram" and #new_args >= 2 then
        local trigram_results = trigram_search(new_args[2], MAX_RESULTS)
        print_header("Trigram matches for '" .. new_args[2] .. "':")
        for _, r in ipairs(trigram_results) do
            print_result(r.word, r.def)
        end
        if #trigram_results == 0 then print("(none)") end
    elseif new_args[1] == "--def" and #new_args >= 2 then
        definition_search(new_args[2])
    elseif new_args[1] == "--html" and #new_args >= 2 then
        handle_html(new_args[2])
    elseif new_args[1] == "--help" or new_args[1] == "-h" then
        show_usage()
    else
        local query = new_args[1]
        if exact_mode then
            exact_search(query)
        else
            fuzzy_and_prefix_wrapper(query, no_fuzzy)
        end
    end

    close_db()
end

-- run
if pcall(require, "luasql.sqlite3") then
    local args = {}
    for i = 1, #arg do args[i] = arg[i] end
    main(args)
else
    print("Error: luasql.sqlite3 module not found.")
    print("Install it with: luarocks install luasql-sqlite3")
    os.exit(1)
end
