module main

import os
import json2

$if windows {
	// Use SDK declarations for the helper's Windows runtime dependencies.
	#include <windows.h>
}

// Tokenization, UTF-8 decoding, and bounded byte comparison are reused from
// GUI's issue74 helper. The VGlyph verifier below retains its own link contract.
const max_compare_file_size = u64(8 * 1024 * 1024)

struct LinkConfig {
	generation  string
	linkage     string
	mode        string
	lane        string
	log_path    string
	cc          string
	cxx         string
	output      string
	record_path string
}

struct LinkResponse {
	path       string
	payload    string
	generation string
}

struct LinkCommand {
	line_index    int
	driver        string
	expanded      []string
	outputs       []string
	compile_only  bool
	transport     string
	response_path string
}

// Keep the original nine JSON fields, in the reference writer's key order.
struct LinkRecord {
	driver            string
	driver_basename   string
	expanded_argv     []string
	generation        string
	link_output_token string
	linkage           string
	output_basename   string
	response_path     string
	transport         string
}

fn bytes_equal(left []u8, right []u8) bool {
	if left.len != right.len {
		return false
	}
	for index in 0 .. left.len {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}

fn same_file_identity(left os.Stat, right os.Stat) bool {
	// Reading may update atime. Every other stable identity and content field is
	// required to remain unchanged across lstat/open/read/lstat.
	return left.dev == right.dev && left.inode == right.inode && left.mode == right.mode
		&& left.nlink == right.nlink && left.uid == right.uid && left.gid == right.gid
		&& left.rdev == right.rdev && left.size == right.size && left.mtime == right.mtime
		&& left.ctime == right.ctime
}

fn read_open_file_bounded(path string, ordinal int, expected_size int) ![]u8 {
	mut file := os.open(path) or { return error('compare-files input ${ordinal} open failed') }
	defer {
		file.close()
	}
	mut content := []u8{len: expected_size + 1}
	mut content_len := 0
	for content_len < content.len {
		read_count := file.read(mut content[content_len..]) or {
			if err is os.Eof {
				break
			}
			return error('compare-files input ${ordinal} read failed')
		}
		if read_count <= 0 {
			return error('compare-files input ${ordinal} returned an invalid read length')
		}
		content_len += read_count
	}
	if content_len != expected_size {
		return error('compare-files input ${ordinal} changed size while being read')
	}
	return content[..content_len].clone()
}

fn read_compare_file(path string, ordinal int) ![]u8 {
	if path == '' {
		return error('compare-files input ${ordinal} is not a regular non-link file')
	}
	before := os.lstat(path) or {
		return error('compare-files input ${ordinal} metadata read failed')
	}
	if before.get_filetype() != .regular || os.is_link(path) {
		return error('compare-files input ${ordinal} is not a regular non-link file')
	}
	if before.size > max_compare_file_size {
		return error('compare-files input ${ordinal} exceeds 8388608 bytes')
	}
	first_content := read_open_file_bounded(path, ordinal, int(before.size))!
	after_first_read := os.lstat(path) or {
		return error('compare-files input ${ordinal} metadata re-read failed')
	}
	if after_first_read.get_filetype() != .regular || os.is_link(path)
		|| !same_file_identity(before, after_first_read) {
		return error('compare-files input ${ordinal} changed identity while being read')
	}
	second_content := read_open_file_bounded(path, ordinal, int(before.size))!
	after_second_read := os.lstat(path) or {
		return error('compare-files input ${ordinal} metadata re-read failed')
	}
	if after_second_read.get_filetype() != .regular || os.is_link(path)
		|| !same_file_identity(before, after_second_read) {
		return error('compare-files input ${ordinal} changed identity while being read')
	}
	if !bytes_equal(first_content, second_content) {
		return error('compare-files input ${ordinal} changed content while being read')
	}
	return first_content
}

fn compare_files_cli(arguments []string) int {
	if arguments.len < 2 || arguments.len % 2 != 0 {
		eprintln('usage: verify_final_link compare-files <left> <right> [<left> <right> ...]')
		return 2
	}
	for pair_start := 0; pair_start < arguments.len; pair_start += 2 {
		pair_number := pair_start / 2 + 1
		left := read_compare_file(arguments[pair_start], pair_number * 2 - 1) or {
			eprintln(err.msg())
			return 2
		}
		right := read_compare_file(arguments[pair_start + 1], pair_number * 2) or {
			eprintln(err.msg())
			return 2
		}
		if !bytes_equal(left, right) {
			eprintln('compare-files pair ${pair_number} differs')
			return 1
		}
	}
	return 0
}

fn append_replacement(mut output []u8) {
	output << u8(0xef)
	output << u8(0xbf)
	output << u8(0xbd)
}

fn is_continuation(value u8) bool {
	return value & u8(0xc0) == u8(0x80)
}

// decode_utf8_replace follows the maximal-subpart replacement behavior used
// by the reference UTF-8 decoder with replacement enabled. The parser only interprets
// ASCII syntax after this conversion; valid non-ASCII text remains untouched.
fn decode_utf8_replace(input []u8) string {
	mut output := []u8{cap: input.len}
	mut index := 0
	for index < input.len {
		first := input[index]
		if first < u8(0x80) {
			output << first
			index++
			continue
		}
		if first < u8(0xc2) || first > u8(0xf4) {
			append_replacement(mut output)
			index++
			continue
		}
		width := if first < u8(0xe0) {
			2
		} else if first < u8(0xf0) {
			3
		} else {
			4
		}
		if index + 1 >= input.len {
			append_replacement(mut output)
			index++
			continue
		}
		second := input[index + 1]
		if !is_continuation(second) || (first == u8(0xe0) && second < u8(0xa0))
			|| (first == u8(0xed) && second >= u8(0xa0)) || (first == u8(0xf0) && second < u8(0x90))
			|| (first == u8(0xf4) && second > u8(0x8f)) {
			append_replacement(mut output)
			index++
			continue
		}
		if width == 2 {
			output << first
			output << second
			index += 2
			continue
		}
		if index + 2 >= input.len {
			append_replacement(mut output)
			index += 2
			continue
		}
		third := input[index + 2]
		if !is_continuation(third) {
			append_replacement(mut output)
			index += 2
			continue
		}
		if width == 3 {
			output << first
			output << second
			output << third
			index += 3
			continue
		}
		if index + 3 >= input.len {
			append_replacement(mut output)
			index += 3
			continue
		}
		fourth := input[index + 3]
		if !is_continuation(fourth) {
			append_replacement(mut output)
			index += 3
			continue
		}
		output << first
		output << second
		output << third
		output << fourth
		index += 4
	}
	return output.bytestr()
}

fn split_lines(text string) []string {
	mut lines := []string{}
	mut start := 0
	mut index := 0
	for index < text.len {
		mut separator_size := 0
		value := text[index]
		if value == `\r` {
			separator_size = if index + 1 < text.len && text[index + 1] == `\n` { 2 } else { 1 }
		} else if value == `\n` || value == u8(0x0b) || value == u8(0x0c) || value == u8(0x1c)
			|| value == u8(0x1d) || value == u8(0x1e) {
			separator_size = 1
		} else if value == u8(0xc2) && index + 1 < text.len && text[index + 1] == u8(0x85) {
			separator_size = 2
		} else if value == u8(0xe2) && index + 2 < text.len && text[index + 1] == u8(0x80)
			&& (text[index + 2] == u8(0xa8) || text[index + 2] == u8(0xa9)) {
			separator_size = 3
		}
		if separator_size == 0 {
			index++
			continue
		}
		lines << text[start..index]
		index += separator_size
		start = index
	}
	if start < text.len {
		lines << text[start..]
	}
	return lines
}

fn is_word_space(value u8) bool {
	return value == ` ` || value == `\t` || value == `\r` || value == `\n`
}

fn split_words(text string) ![]string {
	mut result := []string{}
	mut token := []u8{}
	mut quote := u8(0)
	mut started := false
	mut index := 0
	for index < text.len {
		value := text[index]
		if quote == u8(0) && is_word_space(value) {
			if started {
				result << token.bytestr()
				token = []u8{}
				started = false
			}
			index++
			continue
		}
		if value == `'` || value == `"` {
			if quote == u8(0) {
				quote = value
				started = true
				index++
				continue
			}
			if quote == value {
				quote = u8(0)
				index++
				continue
			}
		}
		if value == `\\` && quote != `'` && index + 1 < text.len {
			next := text[index + 1]
			escapable := if quote == `"` {
				next == `"` || next == `\\`
			} else {
				is_word_space(next) || next == `'` || next == `"` || next == `\\`
			}
			if escapable {
				token << next
				started = true
				index += 2
				continue
			}
		}
		token << value
		started = true
		index++
	}
	if quote != u8(0) {
		return error('unterminated quote in showcc text')
	}
	if started {
		result << token.bytestr()
	}
	return result
}

fn token_count(tokens []string, expected string) int {
	mut count := 0
	for token in tokens {
		if token == expected {
			count++
		}
	}
	return count
}

fn define_count(tokens []string, macro string) !int {
	combined := '-D' + macro
	mut count := token_count(tokens, combined)
	for token in tokens {
		if token.starts_with(combined + '=') {
			return error('assigned value is not allowed for -D${macro}')
		}
	}
	for index, token in tokens {
		if token != '-D' {
			continue
		}
		if index + 1 >= tokens.len {
			return error('dangling -D in final invocation')
		}
		operand := tokens[index + 1]
		if operand.starts_with(macro + '=') {
			return error('assigned value is not allowed for -D ${macro}')
		}
		if operand == macro {
			count++
		}
	}
	return count
}

fn driver_basename(path string) string {
	base := path.replace('\\', '/').all_after_last('/').to_lower()
	return if base.ends_with('.exe') { base[..base.len - 4] } else { base }
}

fn normalized_rsp(path string) string {
	return path.replace('\\', '/').trim('"').to_lower()
}

fn driver_is_absolute(path string) bool {
	if path.starts_with('/') {
		return true
	}
	if path.len < 4 || path[1] != u8(58) || (path[2] != u8(47) && path[2] != u8(92)) {
		return false
	}
	drive := path[0]
	return (drive >= u8(65) && drive <= u8(90)) || (drive >= u8(97) && drive <= u8(122))
}

fn normalized_driver(path string) !string {
	raw := path.trim('"')
	if !driver_is_absolute(raw) {
		return error('compiler driver is not absolute: ${path}')
	}
	// Direct argv execution: no shell interpolation and no os.Process.wait().
	result := os.exec(['cygpath', '-aw', raw])
	if result.exit_code != 0 {
		return error('cygpath failed for driver ${path}: ${result.exit_code}: ${result.output}')
	}
	canonical := result.output.trim_space().replace('\\', '/').to_lower()
	if canonical == '' {
		return error('cygpath returned an empty compiler driver')
	}
	return if canonical.ends_with('.exe') { canonical[..canonical.len - 4] } else { canonical }
}

fn normalize_arguments(args []string) ![]string {
	if args.len == 0 {
		return error('missing command or verifier arguments')
	}
	if args[0].starts_with('--') || args[0] in ['compare-files', 'same-output'] {
		return args.clone()
	}
	if args.len == 1 {
		return error('missing command or verifier arguments')
	}
	return args[1..].clone()
}

fn parse_config(args []string) !LinkConfig {
	names := ['--generation', '--linkage', '--mode', '--lane', '--log', '--cc', '--cxx', '--output',
		'--record']
	if args.len != names.len * 2 {
		return error('expected generation, linkage, mode, lane, log, cc, cxx, output and record')
	}
	mut values := map[string]string{}
	for i := 0; i < args.len; i += 2 {
		if args[i] !in names || args[i] in values || args[i + 1] == '' {
			return error('unknown, duplicate or empty verifier argument: ${args[i]}')
		}
		values[args[i]] = args[i + 1]
	}
	for name in names {
		if name !in values {
			return error('missing verifier argument: ${name}')
		}
	}
	if values['--generation'] !in ['v1', 'v3'] || values['--linkage'] !in ['dynamic', 'static']
		|| values['--mode'] !in ['dev', 'prod']
		|| values['--lane'] !in ['ucrt64-gcc', 'ucrt64-clang', 'clang64-clang'] {
		return error('unsupported generation, linkage, mode or lane')
	}
	return LinkConfig{
		generation:  values['--generation']
		linkage:     values['--linkage']
		mode:        values['--mode']
		lane:        values['--lane']
		log_path:    values['--log']
		cc:          values['--cc']
		cxx:         values['--cxx']
		output:      values['--output']
		record_path: values['--record']
	}
}

fn parse_responses(lines []string) ![]LinkResponse {
	mut responses := []LinkResponse{}
	v1_prefix := '> C compiler response file "'
	v3_prefix := '  > C++ linker response file "'
	for i, line in lines {
		if line.starts_with(v1_prefix) && line.ends_with('":') {
			if i + 1 >= lines.len {
				return error('V1 response header has no payload')
			}
			responses << LinkResponse{
				path:       normalized_rsp(line[v1_prefix.len..line.len - 2])
				payload:    lines[i + 1]
				generation: 'v1'
			}
		} else if line.starts_with(v3_prefix) && line.ends_with('":') {
			mut payload := []string{}
			for following in lines[i + 1..] {
				if following.starts_with('"') || following.starts_with("'") {
					payload << following
				} else if payload.len > 0 {
					break
				}
			}
			if payload.len == 0 {
				return error('V3 response header has no payload')
			}
			responses << LinkResponse{
				path:       normalized_rsp(line[v3_prefix.len..line.len - 2])
				payload:    payload.join('\n')
				generation: 'v3'
			}
		}
	}
	return responses
}

fn parse_commands(lines []string, responses []LinkResponse, generation string) ![]LinkCommand {
	mut commands := []LinkCommand{}
	for i, line in lines {
		mut raw := ''
		if line.starts_with('> C compiler cmd: ') {
			raw = line['> C compiler cmd: '.len..]
		} else if line.starts_with('  > ') && !line.starts_with('  > C++ linker response file ') {
			raw = line['  > '.len..]
		} else {
			continue
		}
		tokens := split_words(raw)!
		if tokens.len == 0 || '--version' in tokens[1..] {
			continue
		}
		mut response_tokens := []string{}
		for token in tokens[1..] {
			if token.starts_with('@') {
				response_tokens << token
			}
		}
		mut expanded := tokens.clone()
		mut response_path := ''
		mut transport := 'argv'
		if response_tokens.len > 0 {
			if response_tokens.len != 1 {
				return error('expected one response token')
			}
			if tokens.len != 2 {
				return error('response-file invocation contains external argv beyond driver and @rsp')
			}
			response_path = response_tokens[0][1..]
			mut matches := []LinkResponse{}
			for response in responses {
				if response.path == normalized_rsp(response_path)
					&& response.generation == generation {
					matches << response
				}
			}
			if matches.len != 1 {
				return error('response header/path cardinality mismatch for ${response_path}')
			}
			expanded = [tokens[0]]
			expanded << split_words(matches[0].payload)!
			transport = 'response'
		}
		mut outputs := []string{}
		for pos := 0; pos + 1 < expanded.len; pos++ {
			if expanded[pos] == '-o' {
				outputs << expanded[pos + 1]
			}
		}
		commands << LinkCommand{
			line_index:    i
			driver:        tokens[0]
			expanded:      expanded
			outputs:       outputs
			compile_only:  '-c' in expanded[1..]
			transport:     transport
			response_path: response_path
		}
	}
	return commands
}

fn verify_content(content string, cfg LinkConfig) !LinkRecord {
	lines := split_lines(content)
	responses := parse_responses(lines)!
	commands := parse_commands(lines, responses, cfg.generation)!
	output_basename := driver_basename(cfg.output)
	expected_link_output := if cfg.generation == 'v3' { 'out' } else { output_basename }
	mut candidates := []LinkCommand{}
	mut last_compiler_index := -1
	for command in commands {
		mut matching_outputs := 0
		for output in command.outputs {
			matches := if cfg.generation == 'v3' {
				output == expected_link_output
			} else {
				driver_basename(output) == expected_link_output
			}
			if matches {
				matching_outputs++
			}
		}
		if !command.compile_only && matching_outputs == 1 {
			candidates << command
		}
		if !command.compile_only
			&& driver_basename(command.driver) in [driver_basename(cfg.cc), driver_basename(cfg.cxx)] {
			last_compiler_index = command.line_index
		}
	}
	if candidates.len != 1 {
		return error('final-link candidate cardinality mismatch: ${candidates.len}')
	}
	selected := candidates[0]
	if last_compiler_index < 0 || selected.line_index != last_compiler_index {
		return error('selected final link is not the last non-compile compiler command')
	}
	expected := if cfg.linkage == 'static' { cfg.cxx } else { cfg.cc }
	selected_driver_real := normalized_driver(selected.driver)!
	expected_driver_real := normalized_driver(expected)!
	if selected_driver_real != expected_driver_real {
		return error('final driver mismatch: ${selected_driver_real} != ${expected_driver_real}')
	}
	if driver_basename(selected.driver) != driver_basename(expected) {
		return error('final driver basename mismatch')
	}
	argv := selected.expanded[1..]
	if token_count(argv, '-o') != 1 || '-c' in argv {
		return error('final argv must contain one -o and no -c')
	}
	mut has_input := false
	for token in argv {
		lower := token.to_lower()
		if lower.ends_with('.c') || lower.ends_with('.o') {
			has_input = true
		}
		if token in ['-lstdc++', '-lc++'] {
			return error('named C++ runtime flag is forbidden')
		}
	}
	if !has_input {
		return error('final argv contains no C source or object input')
	}
	for command in commands {
		if command.compile_only && '-fuse-ld=lld' in command.expanded[1..] {
			return error('LLD selection flag leaked into a compile-only command')
		}
	}
	expected_lld := if cfg.generation == 'v3' && cfg.mode == 'prod' && cfg.lane == 'ucrt64-clang' {
		1
	} else {
		0
	}
	if token_count(argv, '-fuse-ld=lld') != expected_lld {
		return error('LLD selection cardinality mismatch')
	}
	for macro in ['GLIB_STATIC_COMPILATION', 'GOBJECT_STATIC_COMPILATION'] {
		expected_count := if cfg.linkage == 'static' { 1 } else { 0 }
		if define_count(argv, macro)! != expected_count {
			return error('-D${macro} cardinality mismatch')
		}
	}
	if cfg.linkage == 'static' {
		if token_count(argv, '-static') != 1 {
			return error('static final argv must contain exactly one -static token')
		}
		mut last_intl := -1
		mut iconv_index := -1
		mut iconv_count := 0
		for i, token in argv {
			if token == '-lintl' {
				last_intl = i
			} else if token == '-liconv' {
				iconv_index = i
				iconv_count++
			}
		}
		if last_intl < 0 || iconv_count != 1 {
			return error('static closure must contain at least one -lintl and exactly one -liconv')
		}
		if last_intl >= iconv_index {
			return error('static closure must place the VGlyph -liconv fallback after every -lintl')
		}
	} else {
		if '-static' in argv {
			return error('dynamic final argv contains -static')
		}
		if '-liconv' in argv {
			return error('dynamic final argv contains -liconv')
		}
	}
	return LinkRecord{
		driver:            selected_driver_real
		driver_basename:   driver_basename(selected.driver)
		expanded_argv:     selected.expanded
		generation:        cfg.generation
		link_output_token: expected_link_output
		linkage:           cfg.linkage
		output_basename:   output_basename
		response_path:     selected.response_path
		transport:         selected.transport
	}
}

fn record_json(record LinkRecord) string {
	// JSON values/schema match the reference. Unicode escape hex casing may
	// differ, so cross-generation equality is checked between the two V helpers.
	return json2.encode(record, escape_unicode: true) + '\n'
}

fn output_basename_from_json(content string) !string {
	value := json2.decode[json2.Any](content, strict: true)!
	if value !is map[string]json2.Any {
		return error('final-link record must be a JSON object')
	}
	record := value as map[string]json2.Any
	basename := record['output_basename'] or {
		return error('final-link record has no output_basename')
	}
	if basename !is string {
		return error('final-link output_basename must be a string')
	}
	return basename as string
}

fn check_output_values(records []string) ! {
	if records.len == 0 {
		return error('same-output sequence is empty')
	}
	first := output_basename_from_json(records[0])!
	for record in records[1..] {
		if output_basename_from_json(record)! != first {
			return error('same-output sequence mismatch')
		}
	}
}

fn check_output_group(directory string, generation string, labels []string) ! {
	mut records := []string{}
	for i, label in labels {
		path := os.join_path(directory, '${generation}-${label}.final-link.json')
		content := read_compare_file(path, i + 1)!
		records << content.bytestr()
	}
	check_output_values(records)!
}

fn same_output_cli(args []string) int {
	if args.len != 2 || args[1] !in ['v1', 'v3'] {
		eprintln('usage: verify_final_link same-output <directory> <v1|v3>')
		return 2
	}
	check_output_group(args[0], args[1], ['dynamic-dev-cold', 'dynamic-dev-warm', 'static-dev-cold',
		'static-dev-warm', 'dynamic-dev-again']) or {
		eprintln(err.msg())
		return 1
	}
	check_output_group(args[0], args[1], ['dynamic-prod', 'static-prod']) or {
		eprintln(err.msg())
		return 1
	}
	return 0
}

fn verify_cli(args []string) int {
	cfg := parse_config(args) or {
		eprintln(err.msg())
		return 2
	}
	content := read_compare_file(cfg.log_path, 1) or {
		eprintln(err.msg())
		return 1
	}
	record := verify_content(decode_utf8_replace(content), cfg) or {
		eprintln(err.msg())
		return 1
	}
	encoded := record_json(record)
	os.write_file(cfg.record_path, encoded) or {
		eprintln('could not write final-link record: ${err.msg()}')
		return 1
	}
	print(encoded)
	return 0
}

fn self_expect(condition bool, message string) ! {
	if !condition {
		return error('selftest failed: ${message}')
	}
}

fn expect_verify_error(content string, cfg LinkConfig, fragment string) ! {
	verify_content(content, cfg) or {
		if !err.msg().contains(fragment) {
			return error('selftest unexpected error: ${err.msg()}, wanted ${fragment}')
		}
		return
	}
	return error('selftest accepted invalid link: ${fragment}')
}

fn expect_json_error(content string) ! {
	output_basename_from_json(content) or { return }
	return error('selftest accepted invalid output_basename JSON: ${content}')
}

fn expect_group_error(records []string) ! {
	check_output_values(records) or { return }
	return error('selftest accepted mismatched same-output sequence')
}

fn file_read_fails(path string) bool {
	read_compare_file(path, 1) or { return true }
	return false
}

fn split_words_fails(content string) bool {
	split_words(content) or { return true }
	return false
}

fn output_group_fails(directory string, generation string, labels []string) bool {
	check_output_group(directory, generation, labels) or { return true }
	return false
}

fn self_config(generation string, linkage string, mode string, lane string,
	cc string, cxx string, output string) LinkConfig {
	return LinkConfig{
		generation: generation
		linkage:    linkage
		mode:       mode
		lane:       lane
		cc:         cc
		cxx:        cxx
		output:     output
	}
}

fn self_command(generation string, driver string, args string) string {
	prefix := if generation == 'v1' { '> C compiler cmd: ' } else { '  > ' }
	return prefix + '"${driver}" ' + args
}

fn run_selftest() ! {
	cc := os.getenv('VG_HELPER_CC')
	cxx := os.getenv('VG_HELPER_CXX')
	root := os.getenv('VG_HELPER_SELFTEST_ROOT')
	self_expect(cc != '' && cxx != '' && root != '', 'selftest environment')!
	os.mkdir(root)!
	mut cleanup_files := []string{}
	defer {
		for file in cleanup_files {
			os.rm(file) or {}
		}
		os.rmdir(root) or {}
	}
	left := os.join_path(root, 'left.bin')
	right := os.join_path(root, 'right.bin')
	space_file := os.join_path(root, 'path with spaces.txt')
	cleanup_files << [left, right, space_file]
	os.write_file_array(left, [u8(0), 1, 2, 255])!
	os.write_file_array(right, [u8(0), 1, 2, 255])!
	os.write_file(space_file, 'spaces')!
	self_expect(bytes_equal(read_compare_file(left, 1)!, read_compare_file(right, 2)!),
		'byte equality with NUL and high bytes')!
	os.write_file_array(right, [u8(0), 1, 3, 255])!
	self_expect(!bytes_equal(read_compare_file(left, 1)!, read_compare_file(right, 2)!),
		'byte inequality')!
	os.write_file(right, '')!
	self_expect(read_compare_file(right, 2)!.len == 0, 'empty regular file')!
	missing := os.join_path(root, 'missing.bin')
	self_expect(file_read_fails(missing), 'unreadable file rejection')!
	self_expect(file_read_fails(root), 'directory rejection')!
	canonical_space := normalized_driver(space_file)!
	self_expect(canonical_space.contains('path with spaces.txt'), 'real cygpath path with spaces')!
	self_expect(normalized_driver(space_file.replace('\\', '/'))! == canonical_space,
		'cygpath slash normalization')!
	self_expect(normalized_driver(space_file.replace('/', '\\'))! == canonical_space,
		'cygpath backslash normalization')!
	self_expect(!driver_is_absolute('bin/clang.exe'), 'relative driver rejection')!

	self_expect(normalize_arguments(['helper.exe', '--selftest'])! == ['--selftest'],
		'V1 argv normalization')!
	self_expect(normalize_arguments(['--selftest'])! == ['--selftest'], 'V3 argv normalization')!
	self_expect(normalize_arguments(['helper.exe', 'compare-files', 'a', 'b'])! == [
		'compare-files',
		'a',
		'b',
	], 'V1 compare argv')!
	self_expect(normalize_arguments(['same-output', 'a', 'v3'])! == ['same-output', 'a', 'v3'],
		'V3 same-output argv')!
	self_expect(split_words('"a b" "" \'c d\' x\\ y')! == ['a b', '', 'c d', 'x y'],
		'quoted, empty and escaped argv')!
	self_expect(split_words('"D:\\\\tmp\\\\a"')! == ['D:\\tmp\\a'], 'quoted backslashes')!
	self_expect(split_words_fails('"unterminated'), 'unterminated quote rejection')!
	self_expect(decode_utf8_replace([u8(0xff), 0x61]) == '�a', 'invalid UTF-8 replacement')!
	self_expect(split_lines('a\r\nb\rc\n') == ['a', 'b', 'c'], 'line endings')!

	output := os.join_path(root, 'result output.exe')
	cli_args := ['--generation', 'v1', '--linkage', 'dynamic', '--mode', 'dev', '--lane',
		'ucrt64-gcc', '--log', left, '--cc', cc, '--cxx', cxx, '--output', output, '--record',
		right]
	parsed := parse_config(cli_args)!
	self_expect(parsed.output == output && parsed.cc == cc, 'verifier flag values')!
	mut with_executable := ['helper.exe']
	with_executable << cli_args
	self_expect(normalize_arguments(with_executable)! == cli_args, 'V1 verifier argv')!
	self_expect(normalize_arguments(cli_args)! == cli_args, 'V3 verifier argv')!

	for generation in ['v1', 'v3'] {
		for linkage in ['dynamic', 'static'] {
			for mode in ['dev', 'prod'] {
				for lane in ['ucrt64-gcc', 'ucrt64-clang', 'clang64-clang'] {
					cfg := self_config(generation, linkage, mode, lane, cc, cxx, output)
					driver := if linkage == 'static' { cxx } else { cc }
					link_output := if generation == 'v3' { 'out' } else { '"${output}"' }
					mut args := 'input.o -o ${link_output}'
					if linkage == 'static' {
						args += ' -DGLIB_STATIC_COMPILATION -D GOBJECT_STATIC_COMPILATION'
						args += ' -static -lintl -lintl -liconv'
					}
					if generation == 'v3' && mode == 'prod' && lane == 'ucrt64-clang' {
						args += ' -fuse-ld=lld'
					}
					record := verify_content(self_command(generation, driver, args), cfg)!
					self_expect(record.output_basename == 'result output', 'record output basename')!
					self_expect(record.generation == generation && record.linkage == linkage,
						'record compiler/linkage')!
					encoded := record_json(record)
					self_expect(output_basename_from_json(encoded)! == 'result output',
						'JSON output basename roundtrip')!
					decoded := json2.decode[json2.Any](encoded, strict: true)!
					self_expect(decoded is map[string]json2.Any, 'record JSON object')!
					fields := decoded as map[string]json2.Any
					self_expect(fields.len == 9, 'nine JSON fields')!
					for name in ['driver', 'driver_basename', 'expanded_argv', 'generation',
						'link_output_token', 'linkage', 'output_basename', 'response_path',
						'transport'] {
						self_expect(name in fields, 'record key ${name}')!
					}
				}
			}
		}
	}
	v1 := self_config('v1', 'dynamic', 'dev', 'ucrt64-gcc', cc, cxx, output)
	v3 := self_config('v3', 'dynamic', 'dev', 'clang64-clang', cc, cxx, output)
	static_cfg := self_config('v1', 'static', 'dev', 'ucrt64-gcc', cc, cxx, output)
	good := self_command('v1', cc, 'input.c -o "${output}"')
	good_static := self_command('v1', cxx, 'input.c -o "${output}"' +
		' -DGLIB_STATIC_COMPILATION -DGOBJECT_STATIC_COMPILATION -static -lintl -liconv')
	expect_verify_error('', v1, 'cardinality')!
	expect_verify_error(good + '\n' + good, v1, 'cardinality')!
	expect_verify_error(good + '\n' + self_command('v1', cc, 'other.o -o other.exe'), v1,
		'not the last')!
	expect_verify_error(self_command('v1', cc, '-o "${output}"'), v1, 'no C source or object')!
	expect_verify_error(good + ' -o other.exe', v1, 'one -o')!
	expect_verify_error(good + ' -lstdc++', v1, 'runtime flag')!
	expect_verify_error(good + ' -lc++', v1, 'runtime flag')!
	expect_verify_error(good + ' -static', v1, 'contains -static')!
	expect_verify_error(good + ' -liconv', v1, 'contains -liconv')!
	expect_verify_error(good + ' -DGLIB_STATIC_COMPILATION', v1, 'cardinality')!
	expect_verify_error(good_static + ' -DGLIB_STATIC_COMPILATION', static_cfg, 'cardinality')!
	expect_verify_error(good_static + ' -DGLIB_STATIC_COMPILATION=1', static_cfg, 'assigned value')!
	expect_verify_error(good_static + ' -D GLIB_STATIC_COMPILATION=1', static_cfg, 'assigned value')!
	expect_verify_error(good_static + ' -D', static_cfg, 'dangling')!
	expect_verify_error(good_static + ' -static', static_cfg, 'exactly one -static')!
	expect_verify_error(good_static.replace('-lintl -liconv', '-liconv -lintl'), static_cfg,
		'after every -lintl')!
	expect_verify_error(good_static.replace(' -lintl', ''), static_cfg, 'at least one -lintl')!
	expect_verify_error(good_static.replace(' -liconv', ''), static_cfg, 'exactly one -liconv')!
	expect_verify_error(good_static + ' -liconv', static_cfg, 'exactly one -liconv')!
	expect_verify_error(self_command('v3', cc, 'input.c -c -fuse-ld=lld -o input.o') + '\n' +
		self_command('v3', cc, 'input.o -o out'), v3, 'compile-only')!
	expect_verify_error(self_command('v3', cc, 'input.o -o out -fuse-ld=lld'), v3, 'LLD selection')!
	expect_verify_error(self_command('v1', cxx, 'input.c -o "${output}"'), v1, 'driver mismatch')!

	rsp := os.join_path(root, 'response file.rsp')
	v1_response := self_command('v1', cc, '@"${rsp}"') + '\n' +
		'> C compiler response file "${rsp}":\ninput.c -o "${output}"'
	record_v1 := verify_content(v1_response, v1)!
	self_expect(record_v1.transport == 'response', 'V1 response expansion')!
	v3_response := self_command('v3', cc, '@"${rsp}"') + '\n' +
		'  > C++ linker response file "${rsp}":\n"input.o"\n"-o"\n"out"'
	record_v3 := verify_content(v3_response, v3)!
	self_expect(record_v3.transport == 'response', 'V3 response expansion')!
	expect_verify_error(v1_response.replace('@"${rsp}"', '@"${rsp}" -static'), v1, 'external argv')!
	expect_verify_error(v1_response + '\n> C compiler response file "${rsp}":\ninput.o', v1,
		'response header/path cardinality')!
	expect_verify_error(self_command('v1', cc, '@"${rsp}"'), v1, 'response header/path cardinality')!
	expect_verify_error('> C compiler response file "${rsp}":', v1, 'no payload')!
	expect_verify_error('  > C++ linker response file "${rsp}":', v3, 'no payload')!

	for invalid in ['', '{}', '[]', '{"output_basename":null}', '{"output_basename":1}',
		'{"output_basename":true}', '{"output_basename":{}}', '{"output_basename":[]}',
		'{"output_basename":"x"', '{"output_basename":"x"} trailing'] {
		expect_json_error(invalid)!
	}
	unicode_record := LinkRecord{
		output_basename: 'texte "é😀"\\fin'
	}
	self_expect(output_basename_from_json(record_json(unicode_record))! == unicode_record.output_basename,
		'JSON unicode, quotes and backslash roundtrip')!
	check_output_values(['{"output_basename":"dev"}', '{"output_basename":"dev"}'])!
	expect_group_error(['{"output_basename":"dev"}', '{"output_basename":"other"}'])!
	expect_group_error(['{"output_basename":"dev"}', '{}'])!
	dev := ['dynamic-dev-cold', 'dynamic-dev-warm', 'static-dev-cold', 'static-dev-warm',
		'dynamic-dev-again']
	prod := ['dynamic-prod', 'static-prod']
	for generation in ['v1', 'v3'] {
		for group in [dev, prod] {
			value := if group.len == 5 { 'dev' } else { 'prod' }
			for label in group {
				file := os.join_path(root, '${generation}-${label}.final-link.json')
				cleanup_files << file
				os.write_file(file, '{"output_basename":"${value}"}')!
			}
		}
		self_expect(same_output_cli([root, generation]) == 0,
			'dev-five and prod-two remain separate for ${generation}')!
	}
	dev_bad := os.join_path(root, 'v1-dynamic-dev-warm.final-link.json')
	os.write_file(dev_bad, '{"output_basename":"wrong"}')!
	self_expect(output_group_fails(root, 'v1', dev), 'dev-five divergence')!
	prod_bad := os.join_path(root, 'v3-static-prod.final-link.json')
	os.write_file(prod_bad, '{}')!
	self_expect(output_group_fails(root, 'v3', prod), 'prod-two missing key')!
}

fn main() {
	args := normalize_arguments(arguments()) or {
		eprintln(err.msg())
		exit(2)
	}
	match args[0] {
		'compare-files' {
			exit(compare_files_cli(args[1..]))
		}
		'same-output' {
			exit(same_output_cli(args[1..]))
		}
		'--selftest' {
			if args.len != 1 {
				eprintln('usage: verify_final_link --selftest')
				exit(2)
			}
			run_selftest() or {
				eprintln(err.msg())
				exit(1)
			}
			println('verify_final_link selftest ok')
		}
		else {
			exit(verify_cli(args))
		}
	}
}
