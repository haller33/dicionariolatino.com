import sqlite3
import time
import requests
import re
import hashlib
from html import unescape

# Configuration
DB_NAME = "latin_portuguese.db"
WORDS_FILE = "latin_words_clean.txt"
TARGET_URL = "https://dicionariolatino.com/search.php"
DELAY = 5
RETRY_DELAY = 10  # Seconds to wait when internet is down

def get_hash(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()

def clean_html(raw_html):
    clean = re.sub(r'<[^>]+>', ' ', raw_html)
    return unescape(clean).strip()

def setup_db():
    conn = sqlite3.connect(DB_NAME)
    conn.execute('''CREATE TABLE IF NOT EXISTS dictionary 
                    (word_hash TEXT, word TEXT, content_hash TEXT, 
                     definition TEXT, raw_html TEXT,
                     PRIMARY KEY (word_hash, content_hash))''')
    return conn

def fetch_with_retry(word):
    """Keep trying to fetch until successful, resisting internet drops."""
    while True:
        try:
            response = requests.post(TARGET_URL, data={'query': word}, timeout=15)
            return response
        except (requests.exceptions.ConnectionError, requests.exceptions.Timeout, requests.exceptions.ChunkedEncodingError):
            print(f"\n[!] WiFi down? Waiting {RETRY_DELAY}s to retry '{word}'...")
            time.sleep(RETRY_DELAY)
        except Exception as e:
            print(f"\n[!] Unexpected error: {e}. Retrying...")
            time.sleep(RETRY_DELAY)

def main():
    conn = setup_db()
    cursor = conn.cursor()

    try:
        with open(WORDS_FILE, "r") as f:
            words = [line.strip() for line in f if line.strip()]
    except FileNotFoundError:
        print(f"Error: {WORDS_FILE} not found!")
        return

    print(f"Loaded {len(words)} words. Starting extraction...")

    for word in words:
        word_id_hash = get_hash(word.lower())

        # Resume logic
        cursor.execute("SELECT 1 FROM dictionary WHERE word_hash=?", (word_id_hash,))
        if cursor.fetchone():
            continue

        print(f"Fetching: {word}...", end=" ", flush=True)
        
        # Use the retry logic instead of a single request
        response = fetch_with_retry(word)
        
        if response.status_code == 200:
            html_content = response.text
            if html_content.strip():
                clean_text = clean_html(html_content)
                content_sha = get_hash(html_content)
                
                cursor.execute('''INSERT OR IGNORE INTO dictionary 
                                (word_hash, word, content_hash, definition, raw_html) 
                                VALUES (?, ?, ?, ?, ?)''', 
                               (word_id_hash, word, content_sha, clean_text, html_content))
                conn.commit()
                print(f"OK [{content_sha[:6]}]")
            else:
                print("Empty")
        else:
            print(f"HTTP Error {response.status_code}")

        time.sleep(DELAY)

if __name__ == "__main__":
    main()
