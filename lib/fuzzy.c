// fuzzy.c – fast fuzzy search for Lua 5.2+
// Compile: see build.sh

#include <stdlib.h>
#include <string.h>
#include <math.h>
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

// ---------- Data structures ----------
typedef struct {
    char **strings;
    int *lengths;
    int count;
} WordDict;

static WordDict dict_words = {NULL, NULL, 0};  // for Latin words
static WordDict dict_defs  = {NULL, NULL, 0};  // for Portuguese definitions

static void free_dict(WordDict *d) {
    if (d->strings) {
        for (int i = 0; i < d->count; i++)
            free(d->strings[i]);
        free(d->strings);
        d->strings = NULL;
    }
    if (d->lengths) {
        free(d->lengths);
        d->lengths = NULL;
    }
    d->count = 0;
}

// ---------- Lua API for words ----------
static int l_init_dict(lua_State *L) {
    free_dict(&dict_words);
    luaL_checktype(L, 1, LUA_TTABLE);
    int n = luaL_len(L, 1);
    if (n == 0) {
        lua_pushboolean(L, 1);
        return 1;
    }

    dict_words.strings = malloc(sizeof(char*) * n);
    if (!dict_words.strings) {
        lua_pushboolean(L, 0);
        return 1;
    }
    dict_words.lengths = malloc(sizeof(int) * n);
    if (!dict_words.lengths) {
        free(dict_words.strings);
        lua_pushboolean(L, 0);
        return 1;
    }

    dict_words.count = 0;
    for (int i = 1; i <= n; i++) {
        lua_rawgeti(L, 1, i);
        const char *s = lua_tostring(L, -1);
        if (s) {
            char *dup = strdup(s);
            if (dup) {
                dict_words.strings[dict_words.count] = dup;
                dict_words.lengths[dict_words.count] = strlen(s);
                dict_words.count++;
            }
        }
        lua_pop(L, 1);
    }
    lua_pushboolean(L, 1);
    return 1;
}

// Generic search function using a given dictionary
static int search_in_dict(lua_State *L, WordDict *dict) {
    const char *query = luaL_checkstring(L, 1);
    int max_results = luaL_optint(L, 2, 5);
    if (dict->count == 0 || max_results <= 0) {
        lua_newtable(L);
        return 1;
    }

    typedef struct { int idx; int dist; } HeapItem;
    HeapItem *heap = malloc(sizeof(HeapItem) * (max_results + 1));
    int heap_size = 0;
    size_t qlen = strlen(query);

    for (int i = 0; i < dict->count; i++) {
        const char *str = dict->strings[i];
        size_t slen = dict->lengths[i];

        int len_diff = abs((int)slen - (int)qlen);
        if (heap_size == max_results && len_diff >= heap[0].dist)
            continue;

        int dist = levenshtein(str, query);
        if (heap_size < max_results) {
            int pos = heap_size++;
            heap[pos].idx = i;
            heap[pos].dist = dist;
            while (pos > 0 && heap[(pos-1)/2].dist > heap[pos].dist) {
                HeapItem tmp = heap[(pos-1)/2];
                heap[(pos-1)/2] = heap[pos];
                heap[pos] = tmp;
                pos = (pos-1)/2;
            }
        } else if (dist < heap[0].dist) {
            heap[0].idx = i;
            heap[0].dist = dist;
            int pos = 0;
            while (1) {
                int left = 2*pos+1, right = 2*pos+2, smallest = pos;
                if (left < heap_size && heap[left].dist < heap[smallest].dist) smallest = left;
                if (right < heap_size && heap[right].dist < heap[smallest].dist) smallest = right;
                if (smallest == pos) break;
                HeapItem tmp = heap[pos];
                heap[pos] = heap[smallest];
                heap[smallest] = tmp;
                pos = smallest;
            }
        }
    }

    // Simple insertion sort (K is small)
    for (int i = 0; i < heap_size; i++)
        for (int j = i+1; j < heap_size; j++)
            if (heap[j].dist < heap[i].dist) {
                HeapItem tmp = heap[i];
                heap[i] = heap[j];
                heap[j] = tmp;
            }

    lua_newtable(L);
    for (int i = 0; i < heap_size; i++) {
        lua_newtable(L);
        lua_pushstring(L, dict->strings[heap[i].idx]);
        lua_setfield(L, -2, "word");      // keep field name "word" for compatibility
        lua_pushinteger(L, heap[i].dist);
        lua_setfield(L, -2, "score");
        lua_rawseti(L, -2, i + 1);
    }
    free(heap);
    return 1;
}

static int l_search(lua_State *L) {
    return search_in_dict(L, &dict_words);
}

// ---------- Lua API for definitions ----------
static int l_init_defs(lua_State *L) {
    free_dict(&dict_defs);
    luaL_checktype(L, 1, LUA_TTABLE);
    int n = luaL_len(L, 1);
    if (n == 0) {
        lua_pushboolean(L, 1);
        return 1;
    }

    dict_defs.strings = malloc(sizeof(char*) * n);
    if (!dict_defs.strings) {
        lua_pushboolean(L, 0);
        return 1;
    }
    dict_defs.lengths = malloc(sizeof(int) * n);
    if (!dict_defs.lengths) {
        free(dict_defs.strings);
        lua_pushboolean(L, 0);
        return 1;
    }

    dict_defs.count = 0;
    for (int i = 1; i <= n; i++) {
        lua_rawgeti(L, 1, i);
        const char *s = lua_tostring(L, -1);
        if (s) {
            char *dup = strdup(s);
            if (dup) {
                dict_defs.strings[dict_defs.count] = dup;
                dict_defs.lengths[dict_defs.count] = strlen(s);
                dict_defs.count++;
            }
        }
        lua_pop(L, 1);
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int l_search_def(lua_State *L) {
    return search_in_dict(L, &dict_defs);
}

static int l_free_defs(lua_State *L) {
    free_dict(&dict_defs);
    return 0;
}

static int l_free_dict(lua_State *L) {
    free_dict(&dict_words);
    return 0;
}

// ---------- Module registration ----------
static const luaL_Reg fuzzy_funcs[] = {
    {"init",       l_init_dict},
    {"search",     l_search},
    {"free",       l_free_dict},
    {"init_defs",  l_init_defs},
    {"search_def", l_search_def},
    {"free_defs",  l_free_defs},
    {NULL, NULL}
};

int luaopen_fuzzy(lua_State *L) {
    luaL_newlib(L, fuzzy_funcs);
    return 1;
}
