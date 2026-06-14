# dicionariolatino.com

[![Python Version](https://img.shields.io/badge/python-3.x-blue.svg)](https://www.python.org/)  
[![Lua Version](https://img.shields.io/badge/lua-5.1+-blue.svg)](https://www.lua.org/)  

A Python web scraper that extracts Latin–Portuguese definitions from [DicionarioLatino.com](https://dicionariolatino.com) and stores them in a local SQLite database – plus a **fast, offline Lua search tool** with prefix, fuzzy (Levenshtein), trigram (Jaccard), definition search, and raw HTML export.

## 📖 Project Overview

This repository contains tools to scrape Latin word definitions from the online dictionary **DicionarioLatino.com**. The primary script, `scrap.py`, systematically queries a list of Latin words and saves the results into a structured SQLite database (`latin_portuguese.db`).  

Additionally, a **single‑file Lua program** (`latin.lua`) provides a powerful command‑line interface and REPL to search the database locally. It runs on Lua 5.1+ (including on a **Kindle**) and requires only `luasql.sqlite3` (or the native `sqlite3` module on Kindle).

## ✨ Features

- **Automated Scraping**: Reads a word list (`latin_words_clean.txt`) and submits each term to the dictionary's search endpoint.
- **Robust Retry Logic**: Handles network interruptions and server errors with configurable retry delays.
- **SQLite Storage**: Stores definitions along with raw HTML and SHA‑256 hashes for efficient duplicate avoidance.
- **Resumable Operation**: Skips words already processed, allowing you to stop and restart the scraper without losing progress.
- **Interactive Front‑End**: Includes `custom.js` for a live search interface on a web page.
- **Lua Search Tool** (pure Lua, no compilation required):
  - **Exact match**, **prefix** (word completion), **definition substring** search
  - **Fuzzy search** (Levenshtein distance) – tolerant to typos
  - **Trigram similarity search** (Jaccard index) – finds phonetically similar words
  - **Fuzzy definition search** – find definitions even with misspellings
  - **Raw HTML output** for piping into an HTML dumper or browser
  - **Interactive REPL** with coloured output and persistent settings
  - **Configurable result limit** (`--limit N` or `limit N` in REPL)
  - **Exclusion of problematic content_hash** (`--exclude-bad` or `bad` in REPL)
  - **Unix‑friendly CLI** – works in pipelines, respects TTY colour detection

## 🗂️ Project Structure

| File/Folder                          | Description                                                                 |
|--------------------------------------|-----------------------------------------------------------------------------|
| `scrap.py`                           | Main scraping script: fetches definitions and writes them to the database. |
| `run.sh`                             | Shell script to execute `scrap.py` using `uv` with the `requests` dependency. |
| `custom.js`                          | jQuery‑powered live search for a web front‑end.                           |
| `latin_words_clean.txt`              | Cleaned list of Latin words to scrape.                                     |
| `latin_words.txt`                    | Raw/extended list of Latin words (may contain duplicates).                 |
| `latin_portuguese.db`                | SQLite database (approx. 25 MB) containing scraped definitions.           |
| `source_primary_latin_words.plain_text.txt` | Large raw data file (approx. 21 MB).                               |
| **`latin.lua`**                      | **Lua search client** – offline dictionary lookup with multiple search modes. |

## 🔍 Lua Search Client (`latin.lua`)

### Requirements

- Lua 5.1 or later (tested with 5.1.4 and 5.4)
- `luasql.sqlite3` – install via LuaRocks:  
  `luarocks install luasql-sqlite3`  
  *For Nix users*: `nix-shell -p lua51Packages.luasql-sqlite3 sqlite lua5_1`  
  *For Kindle*: the script will automatically fall back to the built‑in `sqlite3` module.

### Quick Start

```bash
# Interactive REPL
lua latin.lua

# One‑time search (exact + prefix + fuzzy)
lua latin.lua "amor"

# Only exact match
lua latin.lua --exact "amor"

# Prefix only (word completion)
lua latin.lua --prefix "bell"

# Fuzzy search only (Levenshtein distance)
lua latin.lua --fuzzy "amr"

# Trigram similarity search (Jaccard index)
lua latin.lua --trigram "amar"

# Search inside Portuguese definitions (exact substring)
lua latin.lua --def "guerra"

# Fuzzy search inside definitions (typo‑tolerant)
lua latin.lua --def-fuzzy "guerá"

# Output raw HTML for a word
lua latin.lua --html "bellum"

# Exclude a known problematic content hash
lua latin.lua --exclude-bad "amor"

# Combine flags (limit + exclude + no fuzzy)
lua latin.lua --limit 5 --exclude-bad --no-fuzzy "amo"
```

### REPL Commands

Inside the REPL (`lua latin.lua` without arguments):

| Command          | Action                                                              |
|------------------|---------------------------------------------------------------------|
| `?`              | Show help                                                           |
| `q`              | Quit                                                                |
| `limit N`        | Set maximum results to N (e.g. `limit 10`)                          |
| `bad`            | Toggle exclusion of the problematic `content_hash`                  |
| `p:WORD`         | Prefix search (words starting with WORD)                            |
| `f:WORD`         | Fuzzy search (Levenshtein) on word                                  |
| `t:WORD`         | Trigram similarity search (Jaccard) on word                         |
| `d:TEXT`         | Exact substring search inside definitions                           |
| `df:TEXT`        | **Fuzzy search inside definitions** (typo‑tolerant)                 |
| `h:WORD`         | Output raw HTML for the word                                        |
| `WORD`           | Combined search (exact + prefix + fuzzy)                            |

Example REPL session:

```
$ lua latin.lua

Latin Dictionary REPL (universal)
Current result limit: 20
Exclude bad content_hash: false

> p:am
Words starting with 'am':
 • am
 • ama
 • amamus
 ...

> t:amor
Trigram matches for 'amor':
amor: sentimento de afeição, amor...
amoris: do amor...

> df:guerá
Fuzzy definition matches for 'guerá':
bellum: guerra, combate...
bellicus: relativo à guerra...

> bad
Exclude bad content_hash: true

> limit 5
Result limit set to 5

> q
```

### Output Control

- **Colours** are automatically disabled when output is redirected to a file or pipe.
- **Raw HTML** (`--html` or `h:`) prints the exact stored HTML – perfect for piping into an HTML viewer or your own dumper.

## ⚙️ How the Scraper Works

1. **Word List Loading**: The script reads `latin_words_clean.txt` (or a custom file) into memory.
2. **Hashing**: Each word is hashed with SHA‑256 to create a unique identifier.
3. **Database Check**: The script checks if the word hash already exists in the `dictionary` table. If so, it skips that word.
4. **HTTP Request**: For each new word, a POST request is sent to `https://dicionariolatino.com/search.php` with the word as the query parameter.
5. **Response Processing**: Upon a successful `200 OK`, the HTML response is cleaned using regex and `html.unescape()` to extract plain text definitions.
6. **Database Insertion**: The cleaned definition, raw HTML, and hashes are inserted into the `dictionary` table.
7. **Rate Limiting**: A 5‑second delay between requests prevents overloading the dictionary server.

## 🚀 Usage (Scraper)

### Prerequisites
- Python 3.x
- [`uv`](https://github.com/astral-sh/uv) (optional, used by `run.sh`) or pip

### Installation & Execution

1. **Clone the repository**:
       git clone https://github.com/haller33/dicionariolatino.com.git
       cd dicionariolatino.com

2. **Install dependencies** (if not using `uv`):
       pip install requests

3. **Run the scraper**:
    - Using `uv` (recommended): `sh run.sh`
    - Using Python directly: `python scrap.py`

The script will begin processing words and print status updates. The database `latin_portuguese.db` will be created/updated in the same directory.

### Resuming a Partial Run
Simply re-run the script. It checks existing word hashes and only processes missing entries.

## 📦 Dependencies

### For the scraper (Python)
- `requests` – HTTP library for submitting search queries.
- `sqlite3` – Built‑in Python module for database operations.
- `hashlib` – Built‑in module for SHA‑256 hashing.
- `re` and `html` – For cleaning and unescaping HTML content.

### For the Lua search client
- `luasql.sqlite3` (or the native `sqlite3` module on Kindle) – SQLite bindings for Lua.

## ⚠️ Disclaimer

This tool is intended for **educational and personal use only**. Please respect the terms of service of [DicionarioLatino.com](https://dicionariolatino.com). Do not use this scraper in a way that could harm or overload the website. The author is not responsible for any misuse.

## 📄 License

MIT License

## 🙏 Acknowledgments

- Data source: [DicionarioLatino.com](https://dicionariolatino.com)
- Built with Python and Lua

---

*Happy scraping and searching!*
