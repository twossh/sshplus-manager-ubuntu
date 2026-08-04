<?php
declare(strict_types=1);
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
if (str_starts_with($path, '/api/')) {
    require '/opt/sshplus/api/router.php';
    exit;
}
$version = trim((string) @file_get_contents('/opt/sshplus/VERSION')) ?: '5.0.0';
?><!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="robots" content="noindex,nofollow">
  <title>SSHPlus Manager</title>
  <link rel="stylesheet" href="/assets/app.css?v=<?=htmlspecialchars($version, ENT_QUOTES)?>">
</head>
<body>
<div id="loginView" class="auth-shell">
  <form id="loginForm" class="auth-card" autocomplete="on">
    <div class="brand-mark">S+</div>
    <p class="eyebrow">SERVIDOR SEGURO</p>
    <h1>SSHPlus Manager</h1>
    <p class="muted">Administração local do Ubuntu 24.04/26.04 LTS</p>
    <label>Usuário<input name="username" autocomplete="username" required></label>
    <label>Senha<input name="password" type="password" autocomplete="current-password" required></label>
    <button type="submit">Entrar</button>
    <p id="loginError" class="form-error" role="alert"></p>
  </form>
</div>
<div id="appView" class="app-shell hidden">
  <aside class="sidebar">
    <div class="brand"><span class="brand-mark small">S+</span><div><strong>SSHPlus</strong><small>Manager <?=htmlspecialchars($version)?></small></div></div>
    <nav id="nav">
      <button data-page="dashboard" class="active">Visão geral</button>
      <button data-page="users">Usuários</button>
      <button data-page="services">Serviços</button>
      <button data-page="backups">Backups</button>
      <button data-page="updates">Atualizações</button>
      <button data-page="servers">Servidores</button>
      <button data-page="audit">Auditoria</button>
    </nav>
    <div class="sidebar-foot"><span id="currentUser"></span><button id="logoutBtn" class="text-button">Sair</button></div>
  </aside>
  <main>
    <header class="topbar"><div><p class="eyebrow">CONTROLE DO SERVIDOR</p><h2 id="pageTitle">Visão geral</h2></div><div class="live"><span></span>Atualização automática</div></header>
    <section id="content" aria-live="polite"></section>
  </main>
</div>
<div id="toast" class="toast hidden"></div>
<script src="/assets/app.js?v=<?=htmlspecialchars($version, ENT_QUOTES)?>" defer></script>
</body>
</html>
