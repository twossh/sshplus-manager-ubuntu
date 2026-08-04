PRAGMA journal_mode=DELETE;
PRAGMA synchronous=NORMAL;
PRAGMA foreign_keys=ON;
PRAGMA busy_timeout=5000;

CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    applied_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
    username TEXT PRIMARY KEY COLLATE NOCASE,
    max_sessions INTEGER NOT NULL DEFAULT 1 CHECK (max_sessions > 0),
    expires_at INTEGER NOT NULL DEFAULT 0 CHECK (expires_at >= 0),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    user_type TEXT NOT NULL DEFAULT 'normal' CHECK (user_type IN ('normal','test','migrated')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','blocked','expired','missing'))
);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
CREATE INDEX IF NOT EXISTS idx_users_expires_at ON users(expires_at);

CREATE TABLE IF NOT EXISTS audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at INTEGER NOT NULL,
    actor TEXT NOT NULL DEFAULT 'system',
    source TEXT NOT NULL DEFAULT 'cli',
    action TEXT NOT NULL,
    target TEXT NOT NULL DEFAULT '',
    success INTEGER NOT NULL DEFAULT 1 CHECK (success IN (0,1)),
    details TEXT NOT NULL DEFAULT '',
    remote_addr TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_audit_created_at ON audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_logs(action);

CREATE TABLE IF NOT EXISTS app_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS api_users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE COLLATE NOCASE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'admin' CHECK (role IN ('admin','operator','viewer')),
    active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    last_login_at INTEGER
);

CREATE TABLE IF NOT EXISTS servers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    endpoint TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'unknown' CHECK (status IN ('online','offline','unknown')),
    is_local INTEGER NOT NULL DEFAULT 0 CHECK (is_local IN (0,1)),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_servers_local ON servers(is_local) WHERE is_local = 1;

CREATE TABLE IF NOT EXISTS metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    recorded_at INTEGER NOT NULL,
    cpu_load REAL NOT NULL DEFAULT 0,
    memory_used_bytes INTEGER NOT NULL DEFAULT 0,
    memory_total_bytes INTEGER NOT NULL DEFAULT 0,
    disk_used_bytes INTEGER NOT NULL DEFAULT 0,
    disk_total_bytes INTEGER NOT NULL DEFAULT 0,
    rx_bytes INTEGER NOT NULL DEFAULT 0,
    tx_bytes INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_metrics_recorded_at ON metrics(recorded_at DESC);

CREATE TABLE IF NOT EXISTS backups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    filename TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL,
    size_bytes INTEGER NOT NULL DEFAULT 0,
    sha256 TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'ready' CHECK (status IN ('ready','invalid','restored'))
);

INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (1, unixepoch());
INSERT OR IGNORE INTO app_config(key, value, updated_at) VALUES ('schema_version', '1', unixepoch());
INSERT OR IGNORE INTO servers(name, endpoint, status, is_local, created_at, updated_at)
VALUES ('Servidor local', 'local', 'online', 1, unixepoch(), unixepoch());
PRAGMA user_version=1;
