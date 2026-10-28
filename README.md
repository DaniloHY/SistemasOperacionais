# Sistemas Operacionais

Exercícios práticos da disciplina de **Sistemas Operacionais** do curso de Ciência da Computação (Senac), escritos em **Zig 0.16.0** e C e executados em uma VM **Alpine Linux**.

| Projeto | Tema | Linguagem |
|---|---|---|
| [`projeto1`](projeto1) | Primeiro programa em C | C |
| [`projeto2`](projeto2) | Identificação da assinatura do MBR (little/big endian) | Zig |
| [`projeto3`](projeto3) | Processos zumbi e órfão | Zig |
| [`projeto4`](projeto4) | Mini shell com `fork`, `execve` e `waitpid` | Zig |

## Ambiente

- **Sistema:** Alpine Linux (VirtualBox), acessado por SSH
- **Linguagem:** Zig 0.16.0, versão fixada em cada projeto pelo `mise.toml`
- **Commits:** assinados com GPG

Para compilar qualquer projeto em Zig:

```sh
cd projetoN
zig build-exe arquivo.zig
```

---

## Projeto 1: Primeiro programa em C

Programa mínimo que imprime uma mensagem na tela.

```sh
cd projeto1
zig cc main.c -o main   # ou: gcc main.c -o main
./main
```

```
Salve
```

---

## Projeto 2: Assinatura do MBR

Lê os **512 primeiros bytes** de um arquivo (o setor do MBR) e verifica a assinatura nos bytes **510 e 511**:

| Bytes 510 e 511 | Resultado |
|---|---|
| `55 AA` | MBR little endian (padrão de PC) |
| `AA 55` | MBR big endian |
| outros valores | não é MBR |
| arquivo com menos de 512 bytes | não é MBR |

A assinatura é o número `0xAA55`. Em **little endian** o byte menos significativo vem primeiro, então no disco ela aparece como `55 AA`.

```sh
cd projeto2
./teste.sh
```

O `teste.sh` compila o programa, gera quatro arquivos de teste e roda um caso de cada:

```
== Caso 1: le.img (55 AA) ==
MBR little endian (55 AA)
== Caso 2: be.img (AA 55) ==
MBR big endian (AA 55)
== Caso 3: nada.img (sem assinatura) ==
Nao e MBR: assinatura nao encontrada
== Caso 4: pequeno.img (menos de 512 bytes) ==
Nao e MBR: arquivo com menos de 512 bytes
```

---

## Projeto 3: Processos zumbi e órfão

Demonstra os dois estados usando chamadas de sistema diretas (`fork`, `waitpid`, `getpid`, `getppid`). O próprio programa confirma o resultado lendo as linhas `State` e `PPid` de `/proc/PID/status`.

**Zumbi:** o filho termina, mas o pai **não chama `wait()`**. O kernel libera a memória e os arquivos do filho, mas mantém o PCB (`task_struct`) com o código de saída, no estado `Z`. Quando o pai finalmente chama `waitpid()`, ocorre a coleta (*reaping*) e o PCB é destruído.

**Órfão:** o pai termina **antes** do filho. O filho continua vivo e é adotado pelo `init` (PID 1), que passa a ser responsável por coletá-lo.

```sh
cd projeto3
zig build-exe processos.zig
./processos zumbi
./processos orfao
```

```
[pai   1234] o filho 1235 terminou, mas eu NÃO chamei wait().
           /proc/1235/status -> State: Z | PPid: 1234
           ==> CONFIRMADO: o processo 1235 é ZUMBI (estado Z).
[pai   1234] waitpid() coletou o filho 1235 (código de saída 0).
           ==> /proc/1235 não existe mais: o filho foi coletado e o PCB destruído.
```

```
[filho 1241] meu pai 1240 terminou.
           /proc/1241/status -> State: R | PPid: 1
           ==> CONFIRMADO: sou ÓRFÃO. Fui adotado pelo processo 1 (PID 1 é o init).
```

---

## Projeto 4: Mini shell

Um shell simples que executa comandos procurando o executável em um **PATH fixo**:

```
/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin
```

### Como funciona

1. Mostra o prompt `minishell>` e lê a linha digitada.
2. Separa a linha em palavras, montando o `argv` terminado em `null` que o `execve` espera.
3. Procura o comando em cada pasta do PATH, na ordem, e usa o primeiro arquivo executável encontrado.
4. Cria um processo filho com **`fork()`**.
5. O filho troca o próprio programa pelo comando com **`execve()`**.
6. O pai espera com **`waitpid()`**, mostra o código de saída do filho e volta ao prompt.

`cd` e `exit` são **comandos embutidos**: rodam no próprio shell, sem `fork`. Um `cd` executado num processo filho mudaria só o diretório do filho, que termina logo em seguida.

```sh
cd projeto4
zig build-exe minishell.zig
./minishell
```

```
minishell> echo ola mundo
ola mundo
[shell 2539] filho 2568 (/bin/echo) terminou com código 0
minishell> zig version
0.16.0
[shell 2539] filho 2551 (/usr/bin/zig) terminou com código 0
minishell> mkdir
Usage: mkdir [-m MODE] [-p] DIRECTORY...
[shell 2539] filho 2545 (/bin/mkdir) terminou com código 1
minishell> main.zig
main.zig: comando não encontrado
minishell> exit
```

---

**Autor:** Leonardo Rodrigues de Lima ([@leolima92](https://github.com/leolima92))
