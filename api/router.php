<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';
require_once __DIR__ . '/AgentClient.php';

$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

try {
    if ($path === '/api/health' && $method === 'GET') {
        json_response(['ok' => true, 'version' => version()]);
    }

    if ($path === '/api/login' && $method === 'POST') {
        $data = json_input();
        $username = trim((string) ($data['username'] ?? ''));
        $password = (string) ($data['password'] ?? '');
        usleep(250000);
        $account = find_auth_account($username);
        if (!$account || ($account['active'] ?? false) !== true || !password_verify($password, (string) ($account['password_hash'] ?? ''))) {
            AgentClient::call('audit.write', ['actor' => $username ?: 'unknown', 'event' => 'auth.failed', 'target' => $username, 'success' => 0]);
            json_response(['ok' => false, 'error' => 'Usuário ou senha inválidos.'], 401);
        }
        session_regenerate_id(true);
        $_SESSION['user'] = ['username' => $account['username'], 'role' => $account['role']];
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
        AgentClient::call('audit.write', ['event' => 'auth.login', 'target' => $account['username'], 'success' => 1]);
        json_response(['ok' => true, 'user' => $_SESSION['user'], 'csrf' => $_SESSION['csrf']]);
    }

    if ($path === '/api/logout' && $method === 'POST') {
        $user = require_auth();
        require_csrf();
        AgentClient::call('audit.write', ['event' => 'auth.logout', 'target' => $user['username'], 'success' => 1]);
        $_SESSION = [];
        if (ini_get('session.use_cookies')) {
            $params = session_get_cookie_params();
            setcookie(session_name(), '', time() - 42000, $params['path'], $params['domain'] ?? '', (bool) $params['secure'], (bool) $params['httponly']);
        }
        session_destroy();
        json_response(['ok' => true]);
    }

    if ($path === '/api/me' && $method === 'GET') {
        $user = require_auth();
        json_response(['ok' => true, 'user' => $user, 'csrf' => csrf_token(), 'version' => version()]);
    }

    $user = require_auth();
    $isWrite = in_array($method, ['POST', 'PUT', 'PATCH', 'DELETE'], true);
    if ($isWrite) {
        require_csrf();
    }

    $routes = [
        'GET /api/status' => ['status', []],
        'GET /api/metrics' => ['metrics.list', []],
        'GET /api/users' => ['users.list', []],
        'POST /api/users' => ['users.create', ['admin', 'operator']],
        'PATCH /api/users' => ['users.update', ['admin', 'operator']],
        'DELETE /api/users' => ['users.delete', ['admin']],
        'GET /api/services' => ['services.list', []],
        'POST /api/services/restart' => ['services.restart', ['admin', 'operator']],
        'GET /api/audit' => ['audit.list', ['admin', 'viewer', 'operator']],
        'GET /api/backups' => ['backups.list', ['admin', 'operator']],
        'POST /api/backups' => ['backups.create', ['admin']],
        'GET /api/updates' => ['updates.check', ['admin', 'operator']],
        'POST /api/updates/apply' => ['updates.apply', ['admin']],
        'GET /api/rollbacks' => ['rollbacks.list', ['admin']],
        'POST /api/rollbacks/apply' => ['rollbacks.apply', ['admin']],
        'GET /api/servers' => ['servers.list', []],
        'POST /api/servers' => ['servers.create', ['admin']],
        'DELETE /api/servers' => ['servers.delete', ['admin']],
    ];
    $key = $method . ' ' . $path;
    if (!isset($routes[$key])) {
        json_response(['ok' => false, 'error' => 'Rota não encontrada.'], 404);
    }
    [$action, $roles] = $routes[$key];
    if ($roles !== [] && !in_array($user['role'], $roles, true)) {
        json_response(['ok' => false, 'error' => 'Permissão insuficiente.'], 403);
    }
    $payload = $isWrite ? json_input() : $_GET;
    $result = AgentClient::call($action, $payload);
    json_response($result, ($result['ok'] ?? false) ? 200 : 400);
} catch (Throwable $e) {
    error_log('SSHPlus API: ' . $e->getMessage());
    json_response(['ok' => false, 'error' => 'Erro interno da API.'], 500);
}
