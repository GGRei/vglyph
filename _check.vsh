#!/usr/bin/env -S v

import os

fn sh(cmd string) {
	println('> ${cmd}')
	print(execute_or_exit(cmd).output)
}

fn reset_dir(path string) {
	os.rmdir_all(path) or {}
	os.mkdir_all(path) or { panic(err) }
}

fn link_current_repo(vmodules string) {
	target := os.join_path(vmodules, 'vglyph')
	$if windows {
		sh('cmd /c mklink /J "${target}" "${@DIR}"')
	} $else {
		sh('ln -s "${@DIR}" "${target}"')
	}
}

fn tracked_files() []string {
	output := execute_or_exit('git ls-files').output.trim_space()
	if output == '' {
		return []string{}
	}
	mut files := output.split_into_lines()
	files.sort()
	return files
}

fn tracked_v_files(files []string) []string {
	mut filtered := []string{}
	for file in files {
		if file.ends_with('.v') || file.ends_with('.vsh') {
			filtered << file
		}
	}
	filtered.sort()
	return filtered
}

fn tracked_root_tests(files []string) []string {
	mut filtered := []string{}
	for file in files {
		if file.ends_with('_test.v') && !file.contains('/') && !file.contains('\\') {
			filtered << file
		}
	}
	filtered.sort()
	return filtered
}

fn tracked_examples(files []string) []string {
	mut filtered := []string{}
	for file in files {
		if !file.starts_with('examples/') || !file.ends_with('.v') {
			continue
		}
		rest := file['examples/'.len..]
		if !rest.contains('/') && !rest.contains('\\') {
			filtered << file
		}
	}
	filtered.sort()
	return filtered
}

fn quoted_join(files []string) string {
	mut quoted := []string{}
	for file in files {
		quoted << '"${file}"'
	}
	return quoted.join(' ')
}

unbuffer_stdout()
chdir(@DIR)!
os.setenv('VJOBS', '1', true)

vmodules_docs := os.join_path(os.temp_dir(), 'vglyph-vmodules-docs-local')
vmodules_examples := os.join_path(os.temp_dir(), 'vglyph-vmodules-examples-local')
example_bin_dir := os.join_path(os.temp_dir(), 'vglyph-example-bin-local')

reset_dir(vmodules_docs)
reset_dir(vmodules_examples)
reset_dir(example_bin_dir)
link_current_repo(vmodules_docs)
link_current_repo(vmodules_examples)

files := tracked_files()
fmt_files := tracked_v_files(files)
if fmt_files.len == 0 {
	panic('No tracked V files found')
}

sh('v fmt -verify -inprocess ${quoted_join(fmt_files)}')

os.setenv('VMODULES', vmodules_docs, true)
sh('v check-md README.md docs')

tests := tracked_root_tests(files)
if tests.len == 0 {
	panic('No tracked test files found')
}
println('Test files: ${tests.len}')
for i, file in tests {
	println('[${i + 1}/${tests.len}] ${file}')
}
sh('v -no-parallel test ${quoted_join(tests)}')

os.setenv('VMODULES', vmodules_examples, true)
examples := tracked_examples(files)
if examples.len == 0 {
	panic('No tracked examples found')
}
println('Examples: ${examples.len}')
for i, file in examples {
	base := os.file_name(file)
	name := base[..base.len - 2]
	out := os.join_path(example_bin_dir, name)
	println('[${i + 1}/${examples.len}] ${file}')
	sh('v -no-parallel -path "@vlib|@vmodules|." -o "${out}" "${file}"')
}
