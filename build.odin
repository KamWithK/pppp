package build

import "core:log"
import os "core:os/os2"
import "core:path/filepath"
import "core:slice"
import "core:strings"

EXE :: "pppp"
OUT :: EXE + ".exe" when ODIN_OS == .Windows else EXE
SHADER_FORMATS :: [?]string{"spv", "dxil", "msl", "json"}
EXCLUDE_SHADER_PATTERN :: "common"

main :: proc() {
	context.logger = log.create_console_logger()

	run({"odin", "build", "src", "-debug", "-out:" + OUT, "-error-pos-style:unix"})

	files, err := os.read_all_directory_by_path("src/shaders", context.temp_allocator)
	if err != nil {
		log.errorf("Error reading shader sources: {}", err)
		os.exit(1)
	}
	for file in files {
		if strings.contains(file.name, EXCLUDE_SHADER_PATTERN) {continue}

		for format in SHADER_FORMATS {
			shadercross(file, format)
		}
	}

	if slice.contains(os.args, "run") do run({OUT})
}

shadercross :: proc(file: os.File_Info, format: string) {
	basename := filepath.stem(file.name)
	outfile := filepath.join({"content/shaders", strings.concatenate({basename, ".", format})})
	run({"shadercross", file.fullpath, "-o", outfile})
}

run :: proc(cmd: []string) {
	log.infof("Running {}", cmd)
	code, err := exec(cmd)
	if err != nil {
		log.errorf("Error executing process: {}", err)
		os.exit(1)
	}
	if code != 0 {
		log.errorf("Process exited with non-zero code {}", code)
		os.exit(1)
	}
}

exec :: proc(cmd: []string) -> (code: int, error: os.Error) {
	process := os.process_start(
		{command = cmd, stdin = os.stdin, stdout = os.stdout, stderr = os.stderr},
	) or_return
	state := os.process_wait(process) or_return
	os.process_close(process) or_return
	return state.exit_code, nil
}
