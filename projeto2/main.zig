const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const stdout = std.Io.File.stdout();

    // 1. Pega o nome do arquivo passado na linha de comando
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) {
        try stdout.writeStreamingAll(io, "Uso: main <arquivo>\n");
        return;
    }

    // 2. Abre o arquivo
    const file = try std.Io.Dir.cwd().openFile(io, args[1], .{});
    defer file.close(io);

    // 3. Carrega os primeiros 512 bytes (o setor do MBR) no buffer
    var buffer: [512]u8 = undefined;
    const n = try file.readPositionalAll(io, &buffer, 0);
    if (n < 512) {
        try stdout.writeStreamingAll(io, "Nao e MBR: arquivo com menos de 512 bytes\n");
        return;
    }

    // 4. Confere a assinatura nos bytes 510 e 511
    if (buffer[510] == 0x55 and buffer[511] == 0xAA) {
        try stdout.writeStreamingAll(io, "MBR little endian (55 AA)\n");
    } else if (buffer[510] == 0xAA and buffer[511] == 0x55) {
        try stdout.writeStreamingAll(io, "MBR big endian (AA 55)\n");
    } else {
        try stdout.writeStreamingAll(io, "Nao e MBR: assinatura nao encontrada\n");
    }
}
