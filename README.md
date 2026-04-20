# dicionariolatino.com

[![Python Version](https://img.shields.io/badge/python-3.x-blue.svg)](https://www.python.org/)  
A Python web scraper that extracts Latin–Portuguese definitions from [DicionarioLatino.com](https://dicionariolatino.com) and stores them in a local SQLite database.

## 📖 Project Overview

This repository contains tools to scrape Latin word definitions from the online dictionary **DicionarioLatino.com**. The primary script, `scrap.py`, systematically queries a list of Latin words and saves the results into a structured SQLite database (`latin_portuguese.db`). This enables offline access, data analysis, or integration with other applications.

## ✨ Features

- **Automated Scraping**: Reads a word list (`latin_words_clean.txt`) and submits each term to the dictionary's search endpoint.
- **Robust Retry Logic**: Handles network interruptions and server errors with configurable retry delays.
- **SQLite Storage**: Stores definitions along with raw HTML and SHA-256 hashes for efficient duplicate avoidance.
- **Resumable Operation**: Skips words already processed, allowing you to stop and restart the scraper without losing progress.
- **Interactive Front-End**: Includes `custom.js` for a live search interface on a web page.

## 🗂️ Project Structure

| File/Folder                  | Description                                                                 |
|------------------------------|-----------------------------------------------------------------------------|
| `scrap.py`                   | Main scraping script: fetches definitions and writes them to the database. |
| `run.sh`                     | Shell script to execute `scrap.py` using `uv` with the `requests` dependency. |
| `custom.js`                  | jQuery-powered live search for a web front-end.                  |
| `latin_words_clean.txt`      | Cleaned list of Latin words to scrape.                         |
| `latin_words.txt`            | Raw/extended list of Latin words (may contain duplicates).      |
| `latin_portuguese.db`        | SQLite database (~25 MB) containing scraped definitions.       |
| `source_primary_latin_words.plain_text.txt` | Large raw data file (approx. 21 MB).                    |

## ⚙️ How It Works

1. **Word List Loading**: The script reads `latin_words_clean.txt` (or a custom file) into memory.
2. **Hashing**: Each word is hashed with SHA-256 to create a unique identifier.
3. **Database Check**: The script checks if the word hash already exists in the `dictionary` table. If so, it skips that word.
4. **HTTP Request**: For each new word, a POST request is sent to `https://dicionariolatino.com/search.php` with the word as the query parameter.
5. **Response Processing**: Upon a successful `200 OK`, the HTML response is cleaned using regex and `html.unescape()` to extract plain text definitions.
6. **Database Insertion**: The cleaned definition, raw HTML, and hashes are inserted into the `dictionary` table.
7. **Rate Limiting**: A 5‑second delay between requests prevents overloading the dictionary server.

## 🚀 Usage

### Prerequisites
- Python 3.x
- [`uv`](https://github.com/astral-sh/uv) (optional, used by `run.sh`) or pip

### Installation & Execution

1. **Clone the repository**:
   ```bash
   git clone https://github.com/haller33/dicionariolatino.com.git
   cd dicionariolatino.com
   ```

2. **Install dependencies** (if not using `uv`):
   ```bash
   pip install requests
   ```

3. **Run the scraper**:
   - Using `uv` (recommended): `sh run.sh`
   - Using Python directly: `python scrap.py`

The script will begin processing words and print status updates. The database `latin_portuguese.db` will be created/updated in the same directory.

### Resuming a Partial Run
Simply re-run the script. It checks existing word hashes and only processes missing entries.

## 📦 Dependencies

- `requests` – HTTP library for submitting search queries.
- `sqlite3` – Built‑in Python module for database operations.
- `hashlib` – Built‑in module for SHA‑256 hashing.
- `re` and `html` – For cleaning and unescaping HTML content.

## ⚠️ Disclaimer

This tool is intended for **educational and personal use only**. Please respect the terms of service of [DicionarioLatino.com](https://dicionariolatino.com). Do not use this scraper in a way that could harm or overload the website. The author is not responsible for any misuse.

## 📄 License

MIT License

## 🙏 Acknowledgments

- Data source: [DicionarioLatino.com](https://dicionariolatino.com)
- Built with Python

---

*Happy scraping!*
