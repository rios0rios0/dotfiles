package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"

	sprig "github.com/Masterminds/sprig/v3"
)

func main() {
	repoRoot := findRepoRoot()

	tmplFiles, err := collectTemplates(repoRoot)
	if err != nil {
		fmt.Fprintf(os.Stderr, "[tmplcheck] ERROR: walking repo: %v\n", err)
		os.Exit(1)
	}

	passed, exitCode := parseTemplates(repoRoot, tmplFiles, buildFuncMap())
	fmt.Fprintf(os.Stderr, "[tmplcheck] %d/%d templates parsed successfully\n", passed, len(tmplFiles))

	os.Exit(exitCode)
}

// buildFuncMap returns sprig's functions plus chezmoi's own, as no-op stubs that return safe
// zero values.
func buildFuncMap() template.FuncMap {
	funcMap := sprig.TxtFuncMap()

	chezmoiFuncs := template.FuncMap{
		"onepassword":         func(args ...interface{}) interface{} { return map[string]interface{}{"fields": []interface{}{}} },
		"onepasswordRead":     func(args ...interface{}) string { return "stub-value" },
		"onepasswordDocument": func(args ...interface{}) interface{} { return map[string]interface{}{} },
		"warnf":               func(format string, args ...interface{}) string { return "" },
		"lookPath":            func(name string) string { return "/usr/bin/" + name },
		"stat":                func(name string) interface{} { return nil },
		"glob":                func(pattern string) []string { return nil },
		"joinPath":            func(elem ...string) string { return filepath.Join(elem...) },
		"mozillaInstallHash":  func(path string) string { return "stub-hash" },
		"include":             func(name string, data ...interface{}) string { return "" },
		"includeTemplate":     func(name string, data ...interface{}) string { return "" },
		"output":              func(name string, args ...string) string { return "" },
		"replaceAllRegex":     func(pattern, repl, s string) string { return s },
		"fromToml":            func(text string) interface{} { return map[string]interface{}{} },
		"toToml":              func(value interface{}) string { return "" },
	}
	for k, v := range chezmoiFuncs {
		funcMap[k] = v
	}
	return funcMap
}

// collectTemplates returns every template in the repository, followed by the shared fragments in
// .chezmoitemplates/.
func collectTemplates(repoRoot string) ([]string, error) {
	var tmplFiles []string

	err := filepath.Walk(repoRoot, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return skipDir(repoRoot, path, info)
		}
		if isTemplate(path, info) {
			tmplFiles = append(tmplFiles, path)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	return append(tmplFiles, collectFragments(filepath.Join(repoRoot, ".chezmoitemplates"))...), nil
}

// skipDir skips the .git directory and .github/ci (our own CI files).
func skipDir(repoRoot, path string, info os.FileInfo) error {
	rel, _ := filepath.Rel(repoRoot, path)
	if info.Name() == ".git" || rel == filepath.Join(".github", "ci") {
		return filepath.SkipDir
	}
	return nil
}

// isTemplate reports whether chezmoi renders a file as a template: a .tmpl file, or a
// modify-template, which has no .tmpl suffix: chezmoi recognises it by the
// chezmoi:modify-template marker in a modify_ file.
func isTemplate(path string, info os.FileInfo) bool {
	if filepath.Ext(path) == ".tmpl" {
		return true
	}
	if !strings.HasPrefix(info.Name(), "modify_") {
		return false
	}
	content, err := os.ReadFile(path)
	return err == nil && strings.Contains(string(content), "chezmoi:modify-template")
}

// collectFragments returns the shared template fragments in .chezmoitemplates/, which carry no
// .tmpl extension.
func collectFragments(templatesDir string) []string {
	if info, err := os.Stat(templatesDir); err != nil || !info.IsDir() {
		return nil
	}

	var fragments []string
	filepath.Walk(templatesDir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return err
		}
		fragments = append(fragments, path)
		return nil
	})
	return fragments
}

// parseTemplates parses each file with funcMap, reporting every failure, and returns how many
// parsed and the exit code.
func parseTemplates(repoRoot string, tmplFiles []string, funcMap template.FuncMap) (int, int) {
	exitCode := 0
	passed := 0

	for _, file := range tmplFiles {
		content, err := os.ReadFile(file)
		if err != nil {
			fmt.Fprintf(os.Stderr, "[tmplcheck] ERROR: reading %s: %v\n", file, err)
			exitCode = 1
			continue
		}

		rel, _ := filepath.Rel(repoRoot, file)

		// Parse the template
		_, err = template.New(filepath.Base(file)).Funcs(funcMap).Parse(string(content))
		if err != nil {
			fmt.Fprintf(os.Stderr, "[tmplcheck] FAIL: %s: %v\n", rel, err)
			exitCode = 1
		} else {
			passed++
		}
	}

	return passed, exitCode
}

func findRepoRoot() string {
	// Walk up from the binary's directory to find the repo root
	dir, err := os.Getwd()
	if err != nil {
		// Fallback: assume we're run from .github/ci/cmd/tmplcheck/
		dir, _ = filepath.Abs("../../../..")
		return dir
	}

	// Walk up looking for .chezmoi.yaml.tmpl (unique to this repo)
	for {
		if _, err := os.Stat(filepath.Join(dir, ".chezmoi.yaml.tmpl")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}

	// Fallback: assume 4 levels up from this binary's location
	exe, _ := os.Executable()
	return filepath.Join(filepath.Dir(exe), "../../../..")
}
