package main

import (
	"fmt"
	"os"
	"path/filepath"
	"text/template"

	sprig "github.com/Masterminds/sprig/v3"
)

func main() {
	repoRoot := findRepoRoot()

	// Build function map: sprig functions + chezmoi-specific stubs
	funcMap := sprig.TxtFuncMap()

	// Chezmoi-specific template functions (no-op stubs that return safe zero values)
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
		"output":              func(name string, args ...string) string { return "" },
	}
	for k, v := range chezmoiFuncs {
		funcMap[k] = v
	}

	// Collect all .tmpl files
	var tmplFiles []string

	// Walk from repo root for all .tmpl files
	err := filepath.Walk(repoRoot, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		// Skip .git directory
		if info.IsDir() && info.Name() == ".git" {
			return filepath.SkipDir
		}
		// Skip .github/ci directory (our own CI files)
		rel, _ := filepath.Rel(repoRoot, path)
		if info.IsDir() && rel == filepath.Join(".github", "ci") {
			return filepath.SkipDir
		}
		if !info.IsDir() && filepath.Ext(path) == ".tmpl" {
			tmplFiles = append(tmplFiles, path)
		}
		return nil
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "[tmplcheck] ERROR: walking repo: %v\n", err)
		os.Exit(1)
	}

	// Also collect .chezmoitemplates/ (shared template fragments without .tmpl extension)
	templatesDir := filepath.Join(repoRoot, ".chezmoitemplates")
	if info, err := os.Stat(templatesDir); err == nil && info.IsDir() {
		filepath.Walk(templatesDir, func(path string, info os.FileInfo, err error) error {
			if err != nil || info.IsDir() {
				return err
			}
			tmplFiles = append(tmplFiles, path)
			return nil
		})
	}

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

	fmt.Fprintf(os.Stderr, "[tmplcheck] %d/%d templates parsed successfully\n", passed, len(tmplFiles))

	os.Exit(exitCode)
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
