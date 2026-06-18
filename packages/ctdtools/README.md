# ctdtools

Installable downloader for NES-LTER CTD cruise data.

## Installation

Install only the CTD package directly from Git:

```bash
pip install "ctdtools @ git+https://github.com/anhph95/StingrayTools.git#subdirectory=packages/ctdtools"
```

The complete StingrayTools distribution also includes this package:

```bash
pip install "git+https://github.com/anhph95/StingrayTools.git"
```

## Command-line usage

Display the standalone downloader options:

```bash
ctd-download --help
```

When the complete distribution is installed, the same workflow is available
through the unified command-line interface:

```bash
stingray ctd download --help
```

Use the command help to select cruise identifiers, output locations, and other
download options supported by the installed version.
