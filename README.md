# StingrayTools

StingrayTools is a collection of installable tools for processing, organizing,
and visualizing NES-LTER Stingray / ISIIS sensor and imaging data.

The repository contains three user-facing packages:

- [stingraytools](packages/stingraytools/README.md) processes Stingray sensor and image metadata and produces dashboard-ready data.
- [ctdtools](packages/ctdtools/README.md) downloads NES-LTER CTD cruise data.
- [stingray-dashboard](packages/stingray-dashboard/README.md) provides interactive exploration and Docker deployment of dashboard datasets.

[![DOI](https://zenodo.org/badge/946902610.svg)](https://doi.org/10.5281/zenodo.15025961)

## Installation

Install the complete StingrayTools distribution, including the sensor tools,
CTD tools, and dashboard:

```bash
pip install "git+https://github.com/anhph95/StingrayTools.git"
```

Install only the dashboard:

```bash
pip install "stingray-dashboard @ git+https://github.com/anhph95/StingrayTools.git#subdirectory=packages/stingray-dashboard"
```

Install the dashboard with the Gunicorn production-server dependency:

```bash
pip install "stingray-dashboard[server] @ git+https://github.com/anhph95/StingrayTools.git#subdirectory=packages/stingray-dashboard"
```

Install only the CTD downloader:

```bash
pip install "ctdtools @ git+https://github.com/anhph95/StingrayTools.git#subdirectory=packages/ctdtools"
```

Usage, data-layout, development, and deployment instructions are maintained in
the package READMEs linked above.

## License

StingrayTools is distributed under the MIT License. See [LICENSE](LICENSE).

## Contributors

- Anh Pham
- Sidney Batchelder
- Heidi Sosik
