// fuzzy.c – fast fuzzy search for Lua 5.2+
// Compile: see build.sh

#include <stdlib.h>
#include <string.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

// ---------- Levenshtein distance ----------
static int levenshtein(const char *s, const char *t) {
    size_t n = strlen(s);
    size_t m = strlen(t);
    if (n == 0) return m;
    if (m == 0) return n;

    int v0[m + 1];
    int v1[m + 1];
    for (size_t j = 0; j <= m; j++)
        v0[j] = j;

    for (size_t i = 0; i < n; i++) {
        v1[0] = i + 1;
        for (size_t j = 0; j < m; j++) {
            int cost = (s[i] == t[j]) ? 0 : 1;
            int del = v0[j + 1] + 1;
            int ins = v1[j] + 1;
            int sub = v0[j] + cost;
            v1[j + 1] = (del < ins) ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
        }
        for (size_t j = 0; j <= m; j++)
            v0[j] = v1[j];
    }
    return v0[m];
}

// ---------- Data structure ----------
typedef struct {
    char **words;
    int count;
} WordDict;

static WordDict dict = {NULL, 0};

static void free_dict(void) {
    if (dict.words) {
        for (int i = 0; i < dict.count; i++)
            free(dict.words[i]);
        free(dict.words);
        dict.words = NULL;
        dict.count = 0;
    }
}

// ---------- Lua API ----------
static int l_init_dict(lua_State *L) {
    free_dict();
    luaL_checktype(L, 1, LUA_TTABLE);
    int n = luaL_len(L, 1);           // Lua 5.2+ compatible
    if (n == 0) {
        lua_pushboolean(L, 1);
        return 1;
    }

    dict.words = malloc(sizeof(char*) * n);
    if (!dict.words) {
        lua_pushboolean(L, 0);
        return 1;
    }

    dict.count = 0;
    for (int i = 1; i <= n; i++) {
        lua_rawgeti(L, 1, i);
        const char *w = lua_tostring(L, -1);
        if (w) {
            dict.words[dict.count] = strdup(w);
            dict.count++;
        }
        lua_pop(L, 1);
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int l_search(lua_State *L) {
    const char *query = luaL_checkstring(L, 1);
    int max_results = luaL_optint(L, 2, 5);
    if (dict.count == 0 || max_results <= 0) {
        lua_newtable(L);
        return 1;
    }

    typedef struct {
        const char *word;
        int score;
        int idx;
    } Item;
    Item *items = malloc(sizeof(Item) * dict.count);
    for (int i = 0; i < dict.count; i++) {
        items[i].word = dict.words[i];
        items[i].score = levenshtein(dict.words[i], query);
        items[i].idx = i;
    }

    int limit = (max_results < dict.count) ? max_results : dict.count;
    for (int i = 0; i < limit; i++) {
        int best = i;
        for (int j = i + 1; j < dict.count; j++) {
            if (items[j].score < items[best].score)
                best = j;
        }
        if (best != i) {
            Item tmp = items[i];
            items[i] = items[best];
            items[best] = tmp;
        }
    }

    lua_newtable(L);
    for (int i = 0; i < limit; i++) {
        lua_newtable(L);
        lua_pushstring(L, items[i].word);
        lua_setfield(L, -2, "word");
        lua_pushinteger(L, items[i].score);
        lua_setfield(L, -2, "score");
        lua_rawseti(L, -2, i + 1);
    }
    free(items);
    return 1;
}

static int l_free_dict(lua_State *L) {
    free_dict();
    return 0;
}

static const luaL_Reg fuzzy_funcs[] = {
    {"init",     l_init_dict},
    {"search",   l_search},
    {"free",     l_free_dict},
    {NULL, NULL}
};

int luaopen_fuzzy(lua_State *L) {
    luaL_newlib(L, fuzzy_funcs);
    return 1;
}
