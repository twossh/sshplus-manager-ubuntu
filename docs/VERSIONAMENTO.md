# Versionamento e releases

O projeto usa a sequência `MAJOR.MINOR.PATCH`:

- **PATCH**: correções compatíveis, por exemplo `5.0.0` → `5.0.1`;
- **MINOR**: nova funcionalidade compatível, por exemplo `5.0.1` → `5.1.0`;
- **MAJOR**: alteração incompatível ou migração ampla, por exemplo `5.1.0` → `6.0.0`.

O arquivo `VERSION` é a fonte de verdade. A tag Git correspondente deve ser a
mesma versão com o prefixo `v`, por exemplo:

```text
VERSION: 5.3.0
Tag Git: v5.3.0
```

## Preparar uma correção

```bash
./scripts/prepare-release.sh patch "Corrige validação do domínio SlowDNS"
```

## Preparar uma funcionalidade

```bash
./scripts/prepare-release.sh minor "Adiciona relatório de conexões"
```

## Preparar uma versão principal

```bash
./scripts/prepare-release.sh major "Nova arquitetura de módulos"
```

O script atualiza `VERSION`, cria uma entrada no `CHANGELOG.md`, regenera os
checksums, executa os testes e monta os arquivos em `dist/`.

Depois de revisar:

```bash
git add .
git commit -m "chore(release): v5.3.0"
git push origin main
```

O workflow `.github/workflows/release.yml` cria a tag correspondente quando necessário, gera os artefatos e publica a GitHub Release. Reexecuções da mesma versão atualizam os anexos com segurança, sem duplicar a Release.

## Versão específica

```bash
./scripts/prepare-release.sh set 5.0.0 "Inicia a geração 5"
```

## Apenas consultar ou alterar VERSION

```bash
./scripts/version.sh show
./scripts/version.sh bump patch
./scripts/version.sh set 5.1.0
```

Prefira `prepare-release.sh` para releases oficiais, pois ele também atualiza o
changelog e executa toda a validação.
