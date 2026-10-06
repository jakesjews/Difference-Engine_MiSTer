// SPDX-License-Identifier: GPL-2.0-or-later
// Native, interactive simulation and headless regression of the actual RTL.
#include "Vdifference_engine.h"
#include "verilated.h"
#include <SDL.h>
#include <array>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

using Columns = std::array<std::string, 8>;
static const std::array<Columns, 8> presets = {{
    {{"41", "36", "28", "1464", "360", "15240", "1440", "40320"}},
    {{"0", "1", "2", "0", "0", "0", "0", "0"}},
    {{"0", "1", "0", "6", "0", "0", "0", "0"}},
    {{"0", "1", "1", "0", "0", "0", "0", "0"}},
    {{"0", "1", "0", "126", "0", "1680", "0", "5040"}},
    {{"100", "9999999999999999999999999999999", "0", "0", "0", "0", "0", "0"}},
    {{"9999999999999999999999999999999", "1", "0", "0", "0", "0", "0", "0"}},
    {{"0", "0", "0", "0", "0", "0", "0", "0"}}
}};

static std::string padded(const std::string& value) {
    require(value.size() <= 31, "decimal value exceeds 31 digits");
    return std::string(31 - value.size(), '0') + value;
}
static std::string table_file(const Columns& columns) {
    std::string bytes;
    for (const auto& c : columns) bytes += padded(c) + "\n";
    return bytes;
}

class Simulation {
public:
    Vdifference_engine top;
    uint64_t clocks = 0;
    Simulation() {
        top.clk = 0;
        top.reset = 1;
        top.speed = 3;
        top.menu_preset = 0;
        top.osd_open = 0;
        top.ps2_key = 0;
        top.joystick = 0;
        top.menu_load = top.menu_run = top.menu_step = 0;
        top.downloading = top.download_wr = 0;
        top.download_addr = top.download_data = 0;
        reset();
    }
    ~Simulation() { top.final(); }
    void tick(unsigned n = 1) {
        for (unsigned i = 0; i < n; ++i) {
            top.clk = 0; top.eval();
            top.clk = 1; top.eval();
            ++clocks;
        }
    }
    void reset() { top.reset = 1; tick(8); top.reset = 0; tick(8); }
    void event(unsigned code, bool down) {
        top.ps2_key = ((top.ps2_key ^ 0x400) & 0x400) | (down ? 0x200 : 0) | code;
        tick(4);
    }
    void key(unsigned code) { event(code, true); event(code, false); }
    void joy(unsigned bit) { top.joystick = 1 << bit; tick(4); top.joystick = 0; tick(4); }
    void until(const std::function<bool()>& predicate, uint64_t maximum = 2000000) {
        for (uint64_t n = 0; n < maximum; ++n) {
            if (predicate()) return;
            tick();
        }
        throw std::runtime_error("simulation timeout at clock " + std::to_string(clocks));
    }
    std::string column(unsigned c) const {
        std::string value;
        for (int d = 30; d >= 0; --d) {
            unsigned bit = c * 124 + d * 4;
            unsigned digit = (top.columns[bit / 32] >> (bit % 32)) & 15;
            require(digit <= 9, "invalid BCD digit in engine");
            value += char('0' + digit);
        }
        return value;
    }
    Columns columns() const {
        Columns values;
        for (unsigned c = 0; c < 8; ++c) values[c] = column(c);
        return values;
    }
    unsigned count() const {
        unsigned n = 0;
        for (int digit = 5; digit >= 0; --digit) n = n * 10 + ((top.count >> (digit * 4)) & 15);
        return n;
    }
    void expect(const Columns& expected, const std::string& context) const {
        for (unsigned c = 0; c < 8; ++c)
            require(column(c) == padded(expected[c]), context + ": column " + std::to_string(c));
    }
    void select(unsigned preset) {
        top.menu_preset = preset;
        tick(8);
        top.menu_load = 1; tick(4); top.menu_load = 0; tick(4);
    }
    void phase() {
        auto target = (top.phase + 1) & 3;
        key(0x004);
        until([&] { return !top.busy && top.phase == target; });
        tick(4);
    }
    void crank() {
        auto target = count() + 1;
        key(0x006);
        until([&] { return count() == target && !top.busy && top.phase == 0; });
        tick(4);
    }
    void load(const std::string& bytes, int bad_address = -1, bool simultaneous_start = false) {
        top.downloading = 1;
        if (!simultaneous_start) tick(2);
        for (unsigned i = 0; i < bytes.size(); ++i) {
            top.download_addr = i == unsigned(bad_address) ? i + 1 : i;
            top.download_data = uint8_t(bytes[i]);
            top.download_wr = 1; tick();
            top.download_wr = 0; tick();
        }
        top.downloading = 0; tick(5);
    }
    void synchronize_frame() {
        until([&] { return top.vsync; });
        until([&] { return !top.vsync; });
        until([&] { return top.vsync; });
        until([&] { return top.ce_pixel && top.de; });
    }
    std::vector<uint32_t> frame() {
        synchronize_frame();
        std::vector<uint32_t> pixels;
        pixels.reserve(640 * 480);
        while (pixels.size() != 640 * 480) {
            if (top.ce_pixel && top.de)
                pixels.push_back(0xff000000u | (uint32_t(top.red) << 16) | (uint32_t(top.green) << 8) | top.blue);
            tick();
        }
        return pixels;
    }
    void screenshot(const std::filesystem::path& path) {
        auto pixels = frame();
        std::ofstream output(path, std::ios::binary);
        require(bool(output), "cannot write screenshot " + path.string());
        output << "P6\n640 480\n255\n";
        for (uint32_t pixel : pixels) {
            output.put(char(pixel >> 16)); output.put(char(pixel >> 8)); output.put(char(pixel));
        }
        std::cout << "Captured RTL raster: " << path << '\n';
    }
    void check_video() {
        until([&] { return top.vsync; });
        until([&] { return top.ce_pixel && !top.vsync; });
        unsigned pixels = 0, active = 0, hs_low = 0, vs_low = 0, lines = 0, line_pixels = 0;
        bool previous_de = false, previous_ce = top.ce_pixel;
        bool seen_vsync_high = false;
        while (true) {
            if (top.ce_pixel) {
                if (seen_vsync_high && !top.vsync) break;
                seen_vsync_high |= bool(top.vsync);
                ++pixels;
                hs_low += !top.hsync;
                vs_low += !top.vsync;
                if (top.de) { ++active; ++line_pixels; }
                else require((top.red | top.green | top.blue) == 0, "RGB not blanked outside display");
                if (previous_de && !top.de) {
                    require(line_pixels == 640, "active scanline is not 640 pixels");
                    ++lines; line_pixels = 0;
                }
                previous_de = top.de;
            }
            tick();
            require(bool(top.ce_pixel) != previous_ce, "pixel enable does not divide 50 MHz by two");
            previous_ce = top.ce_pixel;
            require(pixels <= 800 * 525, "video frame too long");
        }
        require(pixels == 800 * 525 && active == 640 * 480 && lines == 480, "incorrect frame geometry");
        require(hs_low == 96 * 525 && vs_low == 2 * 800, "incorrect sync pulse widths");
    }
};

static void regression() {
    Simulation s;
    s.expect(presets[0], "power-on museum table");
    for (unsigned p = 0; p < 8; ++p) {
        s.select(p);
        s.expect(presets[p], "OSD preset " + std::to_string(p));
        require(!s.top.running && s.count() == 0 && s.top.phase == 0, "preset must stop/rehome engine");
    }
    s.key(0x00c); // F4 wraps the keyboard preset independently of stored OSD selection.
    s.expect(presets[0], "F4 wraps blank to museum");
    s.select(1);
    for (unsigned n = 1; n <= 18; ++n) {
        s.crank();
        require(s.column(0) == padded(std::to_string(n * n)), "square table after crank");
    }
    s.key(0x003);
    s.expect(presets[1], "F5 reload");
    s.phase();
    require(s.top.phase == 1 && s.count() == 0, "phase step advanced a full cycle");
    auto partial = s.columns();
    s.key(0x046); // 9 cannot edit at a partial cycle.
    require(s.columns() == partial, "edit accepted between phases");
    s.crank();
    require(s.count() == 1 && s.column(0) == padded("1"), "F2 must finish partial cycle");

    s.select(7);
    s.key(0x046);
    require(s.column(0) == padded("9"), "number key edits units wheel");
    s.key(0x05a);
    require(s.column(0) == padded("0"), "wheel increment wraps 9 to 0");
    s.key(0x066);
    require(s.column(0) == padded("9"), "wheel decrement wraps 0 to 9");
    s.key(0x174); s.key(0x16c); s.key(0x016); // D1, Home, 1.
    require(s.column(1) == "1000000000000000000000000000000", "top wheel selection / edit");
    s.key(0x01e); // Auto-descend digit after entry.
    require(s.column(1) == "1200000000000000000000000000000", "digit entry must move down one wheel");
    s.key(0x00b);
    s.expect(presets[7], "F6 clears engine");

    // Held action keys must not repeatedly toggle run; release is tracked even under OSD.
    s.select(1);
    s.event(0x029, true);
    require(s.top.running, "space starts engine");
    s.event(0x029, true);
    require(s.top.running, "typematic space toggled engine again");
    s.top.osd_open = 1; s.event(0x029, false);
    s.tick(40); auto paused = s.columns();
    s.tick(250000);
    require(s.columns() == paused, "engine runs behind OSD");
    s.key(0x00b);
    require(s.columns() == paused, "keyboard leaks through OSD");
    s.top.osd_open = 0; s.tick(4);
    s.key(0x029);
    require(!s.top.running, "space release lost under OSD");
    s.select(1);
    s.joy(4);
    s.until([&] { return s.count() == 1; }); s.tick(4);
    require(s.column(0) == padded("1"), "gamepad crank");
    s.joy(5); require(s.top.running, "gamepad run");
    s.joy(5); require(!s.top.running, "gamepad pause");
    s.select(1);
    s.top.menu_step = 1; s.tick(4); s.top.menu_step = 0;
    s.until([&] { return s.count() == 1; }); s.tick(4);
    require(s.column(0) == padded("1"), "OSD crank action");

    // Successful files are atomic and F5 restores the loaded custom table.
    Columns custom = presets[2]; custom[0] = "1234567890123456789012345678901";
    s.load(table_file(custom), -1, true);
    require(!s.top.load_error, "valid file rejected");
    s.expect(custom, "full precision .de2 load");
    s.crank(); s.key(0x003);
    s.expect(custom, "custom F5 reload");
    auto before = s.columns();
    auto malformed = table_file(presets[0]); malformed[19] = 'x';
    for (const auto& data : {malformed, table_file(presets[0]).substr(0, 255), table_file(presets[0]) + "0", std::string()}) {
        s.load(data);
        require(s.top.load_error && s.columns() == before, "bad file changed engine or failed to report error");
    }
    s.load(table_file(presets[0]), 40);
    require(s.top.load_error && s.columns() == before, "out-of-order download accepted");
    auto crlf = table_file(presets[0]); crlf[31] = '\r';
    s.load(crlf);
    require(s.top.load_error && s.columns() == before, "incorrect line ending accepted");
    s.load(table_file(presets[0]));
    require(!s.top.load_error, "error does not clear after valid file");
    s.expect(presets[0], "recovered file loader");

    s.key(0x029);
    s.key(0x005); // Help pauses automatic phases, retaining the run switch.
    s.tick(40); before = s.columns(); s.tick(300000);
    require(s.top.running && s.columns() == before, "help must pause engine");
    s.key(0x076);
    s.until([&] { return s.columns() != before; });
    s.reset();
    s.expect(presets[1], "reset restores OSD preset, not a transient custom table");
    s.check_video();
    s.top.reset = 1;
    s.check_video();
    s.top.reset = 0; s.tick(8);
    std::cout << "PASS integration: presets, cranks, phase stepping, wheel edits, PS/2 repeats, gamepad, OSD, file validation, help, reset\n"
              << "PASS video: 640x480 active, 800x525 total, HS=96 pixels, VS=2 lines, continuous through reset\n";
}

static void screenshots(const std::filesystem::path& directory) {
    std::filesystem::create_directories(directory);
    Simulation s;
    s.top.speed = 0;
    s.screenshot(directory / "01-museum-ready.ppm");
    s.top.speed = 3;
    for (int i = 0; i < 12; ++i) s.crank();
    s.screenshot(directory / "02-museum-table.ppm");
    s.select(6); s.phase();
    s.screenshot(directory / "03-carry-warning.ppm");
    s.phase();
    s.screenshot(directory / "04-carry-complete.ppm");
    s.key(0x005);
    s.screenshot(directory / "05-operator-guide.ppm");
}

static unsigned scan_code(SDL_Keycode key) {
    switch (key) {
        case SDLK_SPACE: return 0x029;
        case SDLK_ESCAPE: return 0x076;
        case SDLK_F1: return 0x005;
        case SDLK_F2: return 0x006;
        case SDLK_F3: return 0x004;
        case SDLK_F4: return 0x00c;
        case SDLK_F5: return 0x003;
        case SDLK_F6: return 0x00b;
        case SDLK_LEFT: return 0x16b;
        case SDLK_RIGHT: return 0x174;
        case SDLK_UP: return 0x175;
        case SDLK_DOWN: return 0x172;
        case SDLK_HOME: return 0x16c;
        case SDLK_END: return 0x169;
        case SDLK_RETURN: case SDLK_KP_ENTER: return 0x05a;
        case SDLK_BACKSPACE: case SDLK_MINUS: return 0x066;
        case SDLK_0: return 0x045;
        case SDLK_1: return 0x016;
        case SDLK_2: return 0x01e;
        case SDLK_3: return 0x026;
        case SDLK_4: return 0x025;
        case SDLK_5: return 0x02e;
        case SDLK_6: return 0x036;
        case SDLK_7: return 0x03d;
        case SDLK_8: return 0x03e;
        case SDLK_9: return 0x046;
        default: return 0;
    }
}

static void interactive() {
    require(SDL_Init(SDL_INIT_VIDEO) == 0, SDL_GetError());
    SDL_Window* window = SDL_CreateWindow("Difference Engine No. 2 - RTL simulation - F7 speed / drop .de2",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 1280, 960, SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
    require(window, SDL_GetError());
    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    require(renderer, SDL_GetError());
    SDL_RenderSetLogicalSize(renderer, 640, 480);
    SDL_Texture* texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, 640, 480);
    require(texture, SDL_GetError());
    Simulation s;
    s.top.speed = 2;
    bool quit = false;
    while (!quit) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) quit = true;
            if (event.type == SDL_KEYDOWN || event.type == SDL_KEYUP) {
                unsigned code = scan_code(event.key.keysym.sym);
                if (code) s.event(code, event.type == SDL_KEYDOWN);
                if (event.type == SDL_KEYDOWN && !event.key.repeat && event.key.keysym.sym == SDLK_F7)
                    s.top.speed = (s.top.speed + 1) & 3;
            }
            if (event.type == SDL_DROPFILE) {
                std::ifstream file(event.drop.file, std::ios::binary);
                std::string data((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
                s.load(data);
                SDL_free(event.drop.file);
            }
        }
        if (quit) break;
        auto pixels = s.frame();
        SDL_UpdateTexture(texture, nullptr, pixels.data(), 640 * sizeof(uint32_t));
        SDL_RenderClear(renderer);
        SDL_RenderCopy(renderer, texture, nullptr, nullptr);
        SDL_RenderPresent(renderer);
    }
    SDL_DestroyTexture(texture); SDL_DestroyRenderer(renderer); SDL_DestroyWindow(window); SDL_Quit();
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    try {
        std::string mode = argc > 1 ? argv[1] : "--test";
        if (mode == "--test") regression();
        else if (mode == "--screenshots" && argc == 3) screenshots(argv[2]);
        else if (mode == "--interactive") interactive();
        else throw std::runtime_error("usage: de2_sim --test | --screenshots DIR | --interactive");
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        SDL_Quit();
        return 1;
    }
    return 0;
}
