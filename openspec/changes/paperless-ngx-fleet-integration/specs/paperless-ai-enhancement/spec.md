## ADDED Requirements

### Requirement: paperless-gpt SHALL run as a Podman sidecar container
paperless-gpt SHALL be deployed as a Podman container on `oci-melb-1` (matching the established Karakeep container pattern) with systemd-managed lifecycle, tmpfiles for state persistence, and explicit dependency ordering on Paperless web service.

#### Scenario: paperless-gpt container is running
- **WHEN** Paperless web service is active
- **THEN** the paperless-gpt container is started
- **AND** it communicates with Paperless via REST API at `http://host.containers.internal:8080`

#### Scenario: paperless-gpt persists state
- **WHEN** the container restarts
- **THEN** AI processing queue state and configuration are preserved under a declared data path

### Requirement: paperless-gpt SHALL use the bifrost gateway as its LLM provider
paperless-gpt SHALL be configured with `OPENAI_BASE_URL` pointing to the existing bifrost gateway endpoint, enabling AI auto-titling, auto-tagging, and correspondent detection without deploying a separate Ollama instance. The gateway already provides OpenAI-compatible API for Karakeep.

#### Scenario: Paperless-gpt auto-titles a document
- **WHEN** a new document is consumed by Paperless
- **THEN** paperless-gpt polls the Paperless API for unprocessed documents
- **AND** sends document content to the bifrost gateway for title generation
- **AND** updates the document with an auto-generated title

#### Scenario: Paperless-gpt auto-tags a document
- **WHEN** paperless-gpt processes a document
- **THEN** it classifies the document against known correspondents and document types
- **AND** applies matched tags and correspondents via the Paperless API

### Requirement: paperless-gpt SHALL use docling-serve as its OCR provider
paperless-gpt SHALL be configured with `OCR_PROVIDER: "docling"` pointing to the docling-serve API endpoint, enabling advanced document understanding beyond Tesseract for scanned documents with complex layouts, tables, and mixed formats.

#### Scenario: Docling server is running as a systemd service
- **WHEN** the docling-serve service starts
- **THEN** it binds to a configured address (default `127.0.0.1:8070`)
- **AND** loads document parsing models for OCR and layout analysis

#### Scenario: Paperless-gpt requests OCR from docling-serve
- **WHEN** paperless-gpt encounters a scanned document needing enhanced OCR
- **THEN** it sends the document to docling-serve at `http://host.containers.internal:8070`
- **AND** receives structured document output with text, layout, and table recognition

### Requirement: docling-serve SHALL run as a native NixOS service
docling-serve (`pkgs.docling-serve` from nixpkgs) SHALL run as a declarative systemd service on `oci-melb-1` with memory constraints appropriate for the OCI Free Tier (4GB RAM). ML model loading SHALL be single-worker to minimize memory pressure.

#### Scenario: Docling-serve starts with memory constraints
- **WHEN** the docling-serve service is evaluated
- **THEN** it runs with `UVICORN_WORKERS=1` and `OOMScoreAdjust=200`
- **AND** the service is configured with `Restart=on-failure` for crash resilience
