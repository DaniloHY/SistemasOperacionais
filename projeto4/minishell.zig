//! Mini shell: lê um comando, procura o executável num PATH fixo,
//! cria um processo filho com fork(), troca o programa dele com execve()
//! e espera com waitpid() antes de mostrar o prompt de novo.
//!
//! Comandos embutidos: cd <pasta> e exit.
const std = @import("std");
const linux = std.os.linux;

/// PATH fixo: pastas onde os executáveis são procurados, em ordem.
const path_fixo = "/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin";

/// Ambiente entregue aos programas executados.
const ambiente = [_:null]?[*:0]const u8{ "PATH=" ++ path_fixo, "TERM=xterm" };

const max_args = 32;

pub fn main() void {
    var linha_buf: [1025]u8 = undefined; // até 1024 bytes de comando + terminador
    var argv_buf: [max_args + 1]?[*:0]const u8 = undefined;
    var caminho_buf: [512]u8 = undefined;

    while (true) {
        escrever("minishell> ", .{});

        const n = linux.read(0, &linha_buf, linha_buf.len - 1);
        if (linux.errno(n) != .SUCCESS or n == 0) { // erro ou Ctrl+D
            escrever("\n", .{});
            return;
        }
        linha_buf[n] = 0;

        const argc = separarArgumentos(linha_buf[0..n], &argv_buf);
        if (argc == 0) continue; // linha vazia

        const comando = std.mem.span(argv_buf[0].?);

        // ---- comandos embutidos: rodam no próprio shell, sem fork ----
        if (std.mem.eql(u8, comando, "exit")) return;
        if (std.mem.eql(u8, comando, "cd")) {
            mudarDiretorio(argc, &argv_buf);
            continue;
        }

        // ---- procura o executável no PATH fixo ----
        const caminho = procurarNoPath(comando, &caminho_buf) orelse {
            escrever("{s}: comando não encontrado\n", .{comando});
            continue;
        };

        executar(caminho, @ptrCast(&argv_buf));
    }
}

/// Divide a linha em palavras trocando espaços por 0, para que cada palavra
/// vire uma string terminada em zero, o formato que o execve espera.
fn separarArgumentos(linha: []u8, argv: *[max_args + 1]?[*:0]const u8) usize {
    for (linha) |*c| {
        if (c.* == ' ' or c.* == '\t' or c.* == '\n') c.* = 0;
    }
    var argc: usize = 0;
    for (linha, 0..) |c, i| {
        const inicio_de_palavra = c != 0 and (i == 0 or linha[i - 1] == 0);
        if (inicio_de_palavra and argc < max_args) {
            const palavra: [*:0]const u8 = @ptrCast(&linha[i]);
            argv[argc] = palavra;
            argc += 1;
        }
    }
    argv[argc] = null; // argv termina com null
    return argc;
}

/// Procura `comando` em cada pasta do PATH fixo e devolve o primeiro
/// caminho executável. Se o comando já tem '/', usa como foi digitado.
fn procurarNoPath(comando: [:0]const u8, buf: []u8) ?[*:0]const u8 {
    if (std.mem.indexOfScalar(u8, comando, '/') != null) {
        return if (linux.access(comando.ptr, linux.X_OK) == 0) comando.ptr else null;
    }
    var pastas = std.mem.tokenizeScalar(u8, path_fixo, ':');
    while (pastas.next()) |pasta| {
        const texto = std.fmt.bufPrint(buf, "{s}/{s}\x00", .{ pasta, comando }) catch continue;
        const caminho: [*:0]const u8 = @ptrCast(texto.ptr);
        if (linux.access(caminho, linux.X_OK) == 0) return caminho;
    }
    return null;
}

/// fork + execve + waitpid: o coração de qualquer shell.
fn executar(caminho: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) void {
    const rc = linux.fork();
    if (linux.errno(rc) != .SUCCESS) {
        escrever("erro: fork() falhou\n", .{});
        return;
    }

    if (rc == 0) {
        // ---------- FILHO: troca o próprio programa pelo comando ----------
        _ = linux.execve(caminho, argv, &ambiente);
        // execve só retorna se der erro
        escrever("erro: execve() falhou para {s}\n", .{std.mem.span(caminho)});
        linux.exit_group(127);
    }

    // ---------- PAI: espera o filho terminar ----------
    const filho: linux.pid_t = @intCast(rc);
    var status: u32 = 0;
    _ = linux.waitpid(filho, &status, 0);

    if (linux.W.IFEXITED(status)) {
        escrever("[shell {d}] filho {d} ({s}) terminou com código {d}\n", .{ linux.getpid(), filho, std.mem.span(caminho), linux.W.EXITSTATUS(status) });
    } else if (linux.W.IFSIGNALED(status)) {
        escrever("[shell {d}] filho {d} ({s}) terminou pelo sinal {d}\n", .{ linux.getpid(), filho, std.mem.span(caminho), linux.W.TERMSIG(status) });
    }
}

fn mudarDiretorio(argc: usize, argv: *const [max_args + 1]?[*:0]const u8) void {
    if (argc < 2) {
        escrever("uso: cd <pasta>\n", .{});
        return;
    }
    if (linux.errno(linux.chdir(argv[1].?)) != .SUCCESS) {
        escrever("cd: não foi possível entrar em {s}\n", .{std.mem.span(argv[1].?)});
    }
}

fn escrever(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const texto = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = linux.write(1, texto.ptr, texto.len);
}
