<?php
declare(strict_types=1);

final class AgentClient
{
    public static function call(string $action, array $payload = []): array
    {
        if (!preg_match('/^[a-z][a-z0-9._-]{0,63}$/', $action)) {
            throw new InvalidArgumentException('Ação inválida.');
        }
        $user = current_user();
        $payload['actor'] = $user['username'] ?? ($payload['actor'] ?? 'anonymous');
        $payload['remote_addr'] = client_ip();
        $command = ['/usr/bin/sudo', '-n', '/opt/sshplus/bin/sshplus-agent', $action];
        $pipes = [];
        $process = proc_open($command, [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ], $pipes, null, ['PATH' => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin']);
        if (!is_resource($process)) {
            throw new RuntimeException('Não foi possível iniciar o agente.');
        }
        fwrite($pipes[0], json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR));
        fclose($pipes[0]);
        stream_set_timeout($pipes[1], 600);
        stream_set_timeout($pipes[2], 600);
        $stdout = stream_get_contents($pipes[1]);
        $stderr = stream_get_contents($pipes[2]);
        fclose($pipes[1]);
        fclose($pipes[2]);
        $code = proc_close($process);
        try {
            $result = json_decode((string) $stdout, true, 32, JSON_THROW_ON_ERROR);
        } catch (JsonException) {
            throw new RuntimeException('Resposta inválida do agente: ' . trim((string) $stderr));
        }
        if (!is_array($result)) {
            throw new RuntimeException('Resposta vazia do agente.');
        }
        if ($code !== 0 && !isset($result['error'])) {
            $result = ['ok' => false, 'error' => trim((string) $stderr) ?: 'Falha no agente.', 'code' => $code];
        }
        return $result;
    }
}
