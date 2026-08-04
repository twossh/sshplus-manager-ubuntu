# Como contribuir

Obrigado pelo interesse no SSHPlus Manager.

## Fluxo recomendado

1. Crie uma issue descrevendo o problema ou melhoria.
2. Crie uma branch a partir de `main`:

   ```bash
   git switch -c fix/descrever-correcao
   # ou
   git switch -c feat/descrever-recurso
   ```

3. Faça alterações pequenas e focadas.
4. Execute a validação local:

   ```bash
   make verify
   ```

5. Atualize a documentação e a seção `Unreleased` do `CHANGELOG.md`.
6. Abra um pull request preenchendo o modelo fornecido.

## Padrão de commits

Use mensagens objetivas, preferencialmente com estes prefixos:

- `feat:` nova funcionalidade;
- `fix:` correção de erro;
- `security:` melhoria de segurança;
- `refactor:` reorganização sem mudança funcional;
- `docs:` documentação;
- `test:` testes e validações;
- `chore:` manutenção, release ou infraestrutura.

Exemplo:

```text
fix: preservar chaves do SlowDNS durante atualização
```

## Requisitos técnicos

- Bash compatível com Ubuntu 24.04/26.04;
- arquivos com final de linha LF;
- scripts validados com `bash -n` e ShellCheck;
- serviços validados com `systemd-analyze verify` quando disponível;
- nenhuma senha, chave privada, IP particular ou arquivo `.env` no commit.

## Licenciamento

Ao enviar uma contribuição, você declara que tem direito de fornecê-la ao
projeto e concorda que sua inclusão ficará sujeita à licença vigente do
repositório e à aprovação do mantenedor.
