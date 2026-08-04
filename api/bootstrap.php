<?php
declare(strict_types=1);

const SSHPLUS_AUTH_FILE = '/etc/sshplus/panel-auth.json';
const SSHPLUS_VERSION_FILE = '/opt/sshplus/VERSION';
const SSHPLUS_PHP_ERROR_LOG = '/var/log/sshplus/php-error.log';

ini_set('display_errors', '0');
ini_set('log_errors', '1');
ini_set('expose_php', '0');
if (is_file(SSHPLUS_PHP_ERROR_LOG) && is_writable(SSHPLUS_PHP_ERROR_LOG)) {
    ini_set('error_log', SSHPLUS_PHP_ERROR_LOG);
}

$secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');
session_name('sshplus_session');
session_set_cookie_params([
    'lifetime' => 0,
    'path' => '/',
    'secure' => $secure,
    'httponly' => true,
    'samesite' => 'Strict',
]);
if (session_status() !== PHP_SESSION_ACTIVE && !session_start()) {
    throw new RuntimeException('Não foi possível iniciar a sessão do painel.');
}

function auth_accounts(): array
{
    $raw = @file_get_contents(SSHPLUS_AUTH_FILE);
    if ($raw === false || $raw === '') {
        error_log('Arquivo de autenticação do SSHPlus ausente ou ilegível para o PHP.');
        return [];
    }
    try {
        $document = json_decode($raw, true, 16, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        error_log('Arquivo de autenticação do SSHPlus inválido.');
        return [];
    }
    $accounts = $document['accounts'] ?? [];
    return is_array($accounts) ? $accounts : [];
}

function find_auth_account(string $username): ?array
{
    foreach (auth_accounts() as $account) {
        if (!is_array($account)) {
            continue;
        }
        if (hash_equals((string) ($account['username'] ?? ''), $username)) {
            return $account;
        }
    }
    return null;
}

function json_response(array $payload, int $status = 200): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
    exit;
}

function json_input(): array
{
    $raw = file_get_contents('php://input');
    if ($raw === false || $raw === '') {
        return [];
    }
    if (strlen($raw) > 65536) {
        json_response(['ok' => false, 'error' => 'Requisição muito grande.'], 413);
    }
    try {
        $data = json_decode($raw, true, 32, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        json_response(['ok' => false, 'error' => 'JSON inválido.'], 400);
    }
    if (!is_array($data)) {
        json_response(['ok' => false, 'error' => 'Objeto JSON esperado.'], 400);
    }
    return $data;
}

function current_user(): ?array
{
    return isset($_SESSION['user']) && is_array($_SESSION['user']) ? $_SESSION['user'] : null;
}

function require_auth(array $roles = []): array
{
    $user = current_user();
    if ($user === null) {
        json_response(['ok' => false, 'error' => 'Não autenticado.'], 401);
    }
    if ($roles !== [] && !in_array($user['role'] ?? '', $roles, true)) {
        json_response(['ok' => false, 'error' => 'Permissão insuficiente.'], 403);
    }
    return $user;
}

function csrf_token(): string
{
    if (!isset($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }
    return (string) $_SESSION['csrf'];
}

function require_csrf(): void
{
    $token = $_SERVER['HTTP_X_CSRF_TOKEN'] ?? '';
    if ($token === '' || !hash_equals(csrf_token(), $token)) {
        json_response(['ok' => false, 'error' => 'Token CSRF inválido.'], 419);
    }
}

function client_ip(): string
{
    return substr((string) ($_SERVER['REMOTE_ADDR'] ?? ''), 0, 64);
}

function version(): string
{
    $value = @file_get_contents(SSHPLUS_VERSION_FILE);
    return $value === false ? 'desconhecida' : trim($value);
}

function error_reference(): string
{
    return substr(bin2hex(random_bytes(8)), 0, 12);
}
