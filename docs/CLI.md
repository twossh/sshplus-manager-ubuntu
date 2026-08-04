# Interface CLI

A interface utiliza somente recursos do Bash e comandos padrão do Ubuntu Server.

## Comportamento

- Menus numéricos.
- Senhas lidas sem eco no terminal.
- Confirmações destrutivas com resposta padrão negativa.
- Cores somente quando a saída é um terminal compatível.
- `NO_COLOR=1` desativa toda cor ANSI.
- EOF ou fechamento do terminal encerra o menu sem loop infinito.

## Automação

O menu é interativo, mas o instalador e o desinstalador possuem modo não interativo:

```bash
sudo ./install.sh --yes
sudo ./uninstall.sh --yes
sudo ./uninstall.sh --yes --purge-data
```

O comando principal possui consultas sem menu:

```bash
sudo sshplus --status
sudo sshplus --logs
sudo sshplus --version
sudo sshplus --repair
```

## Diagnóstico pós-instalação

```bash
sudo sshplus --healthcheck
```

Executa verificações somente leitura e retorna código diferente de zero quando
encontra erro crítico. Consulte `docs/HOMOLOGACAO.md`.


## Reparo da integração

```bash
sudo sshplus --repair
```

Reconstrói a configuração principal, os atalhos em `/usr/local`, as unidades e
timers do `systemd`, e executa o reparo do painel. Em instalações parciais sem o
atalho principal, use `/opt/sshplus/bin/sshplus-repair`.
