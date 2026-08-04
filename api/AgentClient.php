<?php
declare(strict_types=1);

final class AgentClient
{
    private const SUDO = '/usr/bin/sudo';
    private const AGENT = '/opt/sshplus/bin/sshplus-agent';

    public static function call(string $action, array $payload = []): array
    {
        if (!preg_match('/^[a-z][a-z0-9._-]{0,63}$/', $action)) {
            throw new InvalidArgumentException('Ação inválida.');
        }
        if (!function_exists('proc_open')) {
            throw new RuntimeException('A função proc_open está indisponível no PHP.');
        }
        if (!is_executable(self::SUDO) || !is_executable(self::AGENT)) {
            throw new RuntimeException('Agente administrativo não instalado ou sem permissão de execução.');
        }

        $user = current_user();
        $payload['actor'] = $user['username'] ?? ($payload['actor'] ?? 'anonymous');
        $payload['remote_addr'] = client_ip();
        $input = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
        if (strlen($input) > 65536) {
            throw new RuntimeException('Carga enviada ao agente excede o limite permitido.');
        }

        $command = [self::SUDO, '-n', '--', self::AGENT, $action];
        $pipes = [];
        $process = proc_open($command, [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ], $pipes, null, [
            'PATH' => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
            'LANG' => 'C',
            'LC_ALL' => 'C',
            'HOME' => '/root',
        ]);
        if (!is_resource($process)) {
            throw new RuntimeException('Não foi possível iniciar o agente administrativo.');
        }

        try {
            $length = strlen($input);
            $written = 0;
            while ($written < $length) {
                $chunk = fwrite($pipes[0], substr($input, $written));
                if ($chunk === false || $chunk === 0) {
                    throw new RuntimeException('Não foi possível enviar dados ao agente administrativo.');
                }
                $written += $chunk;
            }
            fclose($pipes[0]);
            unset($pipes[0]);

            stream_set_timeout($pipes[1], 600);
            stream_set_timeout($pipes[2], 600);
            $stdout = stream_get_contents($pipes[1]);
            $stderr = stream_get_contents($pipes[2]);
            fclose($pipes[1]);
            fclose($pipes[2]);
            unset($pipes[1], $pipes[2]);
            $code = proc_close($process);
            $process = null;
        } finally {
            foreach ($pipes as $pipe) {
                if (is_resource($pipe)) {
                    fclose($pipe);
                }
            }
            if (is_resource($process)) {
                proc_terminate($process);
                proc_close($process);
            }
        }

        $stdout = trim((string) $stdout);
        $stderr = trim((string) $stderr);
        try {
            $result = json_decode($stdout, true, 32, JSON_THROW_ON_ERROR);
        } catch (JsonException) {
            $diagnostic = $stderr !== '' ? $stderr : ($stdout !== '' ? $stdout : 'sem resposta');
            throw new RuntimeException('Resposta inválida do agente: ' . self::sanitizeDiagnostic($diagnostic));
        }
        if (!is_array($result)) {
            throw new RuntimeException('Resposta vazia do agente administrativo.');
        }
        if ($code !== 0 && !isset($result['error'])) {
            $result = [
                'ok' => false,
                'error' => $stderr !== '' ? self::sanitizeDiagnostic($stderr) : 'Falha no agente administrativo.',
                'code' => $code,
            ];
        }
        return $result;
    }

    /** Registra auditoria sem impedir login/logout quando o agente está temporariamente indisponível. */
    public static function audit(array $payload): bool
    {
        try {
            $result = self::call('audit.write', $payload);
            return ($result['ok'] ?? false) === true;
        } catch (Throwable $e) {
            error_log('SSHPlus audit não registrada: ' . $e->getMessage());
            return false;
        }
    }

    private static function sanitizeDiagnostic(string $value): string
    {
        $value = preg_replace('/[\r\n\t]+/', ' ', $value) ?? '';
        $value = preg_replace('/\s+/', ' ', $value) ?? '';
        return substr(trim($value), 0, 300);
    }
}
