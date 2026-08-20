set_project("uart-learning")

local uart_rtl = {
    "rtl/baud_gen.v",
    "rtl/async_fifo.v",
    "rtl/uart_tx.v",
    "rtl/uart_rx.v",
    "rtl/axis_tx.v",
    "rtl/axis_rx.v",
    "rtl/axis_top.v",
}

local function add_iverilog_test(name, top, rtl_files)
    target(name)
        set_kind("phony")
        local output = path.join(os.projectdir(), "sim", name .. ".vvp")

        local function make_iverilog_args()
            local args = {"-g2012", "-s", top, "-o", output}
            for _, rtl_file in ipairs(rtl_files) do
                table.insert(args, path.join(os.projectdir(), rtl_file))
            end
            table.insert(args, path.join(os.projectdir(), "tb", name .. ".sv"))
            return args
        end

        on_build(function ()
            print("[iverilog] compiling " .. name)
            os.mkdir(path.directory(output))
            os.mkdir(path.join(os.projectdir(), "wave"))
            os.execv("iverilog", make_iverilog_args())
            print("[iverilog] output: " .. output)
        end)

        on_run(function ()
            if not os.isfile(output) then
                raise("missing " .. output .. "; run `xmake build " .. name .. "` first")
            end

            print("[vvp] running " .. name)
            os.execv("vvp", {output})
        end)
    target_end()
end

add_iverilog_test("tb_test00", "tb_test00", uart_rtl)
add_iverilog_test("tb_test01", "tb_test01", uart_rtl)
add_iverilog_test("tb_test02", "tb_test02", {"rtl/async_fifo.v"})
