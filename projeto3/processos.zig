//! Demonstração de processos ZUMBI e ÓRFÃOS no Linux.
//! Usa as chamadas de sistema diretamente: fork, exit, waitpid, getpid e getppid.
//! A confirmação é feita lendo /proc/PID/status (linhas State e PPid).
//!
//! Uso:
//!   ./processos zumbi
//!   ./processos orfao
const std = @import("std");
const linux = std.os.linux;

/// Tempo para observar o processo também com `ps`, se quiser.
const segundos_observacao = 10;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) uso();

    if (std.mem.eql(u8, args[1], "zumbi")) {
        zumbi();
    } else if (std.mem.eql(u8, args[1], "orfao")) {
        orfao();
    } else {
        uso();
    }
}

// ------------------------------------------------------------------ ZUMBI

/// O filho termina, mas o pai NÃO chama wait(): o filho vira zumbi.
/// Depois de um tempo o pai faz a coleta (reaping) e o zumbi desaparece.
fn zumbi() void {
    escrever("=== Processo ZUMBI ===\n", .{});
    escrever("[pai   {d}] chamando fork()\n", .{linux.getpid()});

    const filho = criarFilho() orelse {
        // ---------- código do FILHO ----------
        escrever("[filho {d}] meu pai é {d}. Vou terminar agora com exit(0).\n", .{ linux.getpid(), linux.getppid() });
        linux.exit_group(0);
    };

    // ---------- código do PAI ----------
    dormir(1); // dá tempo do filho terminar

    escrever("[pai   {d}] o filho {d} terminou, mas eu NÃO chamei wait().\n", .{ linux.getpid(), filho });
    verificarZumbi(filho);
    escrever("[pai   {d}] esperando {d} segundos antes de coletar...\n", .{ linux.getpid(), segundos_observacao });
    dormir(segundos_observacao);

    // Reaping: o pai lê o status e só então o kernel destrói o PCB
    var status: u32 = 0;
    _ = linux.waitpid(filho, &status, 0);
    escrever("[pai   {d}] waitpid() coletou o filho {d} (código de saída {d}).\n", .{ linux.getpid(), filho, linux.W.EXITSTATUS(status) });
    verificarZumbi(filho);
}

fn verificarZumbi(pid: linux.pid_t) void {
    const st = lerStatus(pid) orelse {
        escrever("           ==> /proc/{d} não existe mais: o filho foi coletado e o PCB destruído.\n", .{pid});
        return;
    };
    escrever("           /proc/{d}/status -> State: {c} | PPid: {d}\n", .{ pid, st.estado, st.ppid });
    if (st.estado == 'Z') {
        escrever("           ==> CONFIRMADO: o processo {d} é ZUMBI (estado Z).\n", .{pid});
    } else {
        escrever("           ==> o processo {d} NÃO está zumbi (estado {c}).\n", .{ pid, st.estado });
    }
}

// ------------------------------------------------------------------ ÓRFÃO

/// O pai termina antes do filho: o filho fica órfão e é adotado
/// pelo init (PID 1) ou por um processo "subreaper".
fn orfao() void {
    escrever("=== Processo ÓRFÃO ===\n", .{});
    escrever("[pai   {d}] chamando fork()\n", .{linux.getpid()});

    const filho = criarFilho() orelse {
        // ---------- código do FILHO ----------
        const eu = linux.getpid();
        const pai_original = linux.getppid();
        escrever("[filho {d}] meu pai é {d}. Vou continuar vivo depois que ele terminar.\n", .{ eu, pai_original });
        _ = mostrarStatus(eu);

        // Espera o pai morrer: o PPID muda quando o filho é adotado
        while (linux.getppid() == pai_original) dormirMs(100);

        escrever("[filho {d}] meu pai {d} terminou.\n", .{ eu, pai_original });
        const st = mostrarStatus(eu);
        if (st != null and st.?.ppid != pai_original) {
            escrever("           ==> CONFIRMADO: sou ÓRFÃO. Fui adotado pelo processo {d} (PID 1 é o init).\n", .{st.?.ppid});
        }

        dormir(segundos_observacao);
        escrever("[filho {d}] terminando. O novo pai faz a coleta, então não viro zumbi.\n", .{eu});
        linux.exit_group(0);
    };

    // ---------- código do PAI ----------
    dormir(1); // deixa o filho imprimir as primeiras mensagens
    escrever("[pai   {d}] vou terminar SEM chamar wait() pelo filho {d}.\n", .{ linux.getpid(), filho });
}

/// Imprime State e PPid do processo e devolve o que leu.
fn mostrarStatus(pid: linux.pid_t) ?Status {
    const st = lerStatus(pid) orelse return null;
    escrever("           /proc/{d}/status -> State: {c} | PPid: {d}\n", .{ pid, st.estado, st.ppid });
    return st;
}

// ------------------------------------------------------------------ /proc

const Status = struct {
    /// R = executando, S = dormindo, Z = zumbi...
    estado: u8,
    ppid: linux.pid_t,
};

/// Lê as linhas "State:" e "PPid:" de /proc/PID/status.
/// Devolve null se o processo não existe mais.
fn lerStatus(pid: linux.pid_t) ?Status {
    var caminho_buf: [64]u8 = undefined;
    const texto = std.fmt.bufPrint(&caminho_buf, "/proc/{d}/status\x00", .{pid}) catch return null;
    const caminho: [*:0]const u8 = @ptrCast(texto.ptr);

    const rc = linux.open(caminho, .{}, 0); // somente leitura
    if (linux.errno(rc) != .SUCCESS) return null;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    var buf: [4096]u8 = undefined;
    const n = linux.read(fd, &buf, buf.len);
    if (linux.errno(n) != .SUCCESS) return null;

    var status = Status{ .estado = '?', .ppid = -1 };
    var linhas = std.mem.splitScalar(u8, buf[0..n], '\n');
    while (linhas.next()) |linha| {
        if (std.mem.startsWith(u8, linha, "State:")) {
            const valor = std.mem.trim(u8, linha["State:".len..], " \t");
            if (valor.len > 0) status.estado = valor[0];
        } else if (std.mem.startsWith(u8, linha, "PPid:")) {
            const valor = std.mem.trim(u8, linha["PPid:".len..], " \t");
            status.ppid = std.fmt.parseInt(linux.pid_t, valor, 10) catch -1;
        }
    }
    return status;
}

// ------------------------------------------------------------------ auxiliares

/// fork(): devolve o PID do filho para o pai e null dentro do filho.
fn criarFilho() ?linux.pid_t {
    const rc = linux.fork();
    if (linux.errno(rc) != .SUCCESS) {
        escrever("Erro: fork() falhou\n", .{});
        linux.exit_group(1);
    }
    if (rc == 0) return null;
    const pid: linux.pid_t = @intCast(rc);
    return pid;
}

fn escrever(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const texto = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = linux.write(1, texto.ptr, texto.len);
}

fn dormir(segundos: isize) void {
    const t = linux.timespec{ .sec = segundos, .nsec = 0 };
    _ = linux.nanosleep(&t, null);
}

fn dormirMs(ms: isize) void {
    const t = linux.timespec{ .sec = 0, .nsec = ms * 1_000_000 };
    _ = linux.nanosleep(&t, null);
}

fn uso() noreturn {
    escrever("Uso: processos zumbi | orfao\n", .{});
    linux.exit_group(2);
}
