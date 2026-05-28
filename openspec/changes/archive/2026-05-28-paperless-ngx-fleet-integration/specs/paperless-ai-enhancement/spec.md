## ADDED Requirements

### Requirement: paperless-gpt SHALL support multi-instance deployment with tag-based OCR routing
A single paperless-gpt instance enforces one fixed OCR provider (`OCR_PROVIDER`). To support both LLM-based and Docling-based OCR, paperless-gpt SHALL support multiple named instances, each with independent tags, ports, state directories, and OCR provider configuration. Instances are defined as an attrset under `services.paperless.paperless-gpt.instances` with the following per-instance configurable fields: `port`, `dataDir`, `manualTag`, `autoTag`, `autoOcrTag`, `pdfOcrCompleteTag`, `ocrProvider`, `llmModel`.

#### Scenario: Two paperless-gpt instances are deployed
- **WHEN** `instances.llm.enable = true` and `instances.docling.enable = true`
- **THEN** two independent Podman containers are started
- **AND** the `llm` instance listens on its configured port (default 5051) and watches `manualTag=paperless-gpt`, `autoTag=paperless-gpt-auto`, `autoOcrTag=ocr-llm`
- **AND** the `docling` instance listens on its configured port (default 5052) and watches only `autoOcrTag=ocr-docling` (inert manual/auto tags to avoid processing overlap)
- **AND** both instances communicate with Paperless via REST API at `http://host.containers.internal:8080` and share the same API token

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

### Requirement: paperless-gpt SHALL support docling-serve as an OCR provider
At least one paperless-gpt instance SHALL be configurable with `OCR_PROVIDER: "docling"` pointing to the docling-serve API endpoint, enabling advanced document understanding beyond Tesseract for scanned documents with complex layouts, tables, and mixed formats. The instance using Docling OCR SHALL use an inert `autoOcrTag` (default `ocr-docling`) to avoid tag collisions with LLM-based OCR instances.

#### Scenario: Docling OCR instance avoids tag collision
- **WHEN** a document is tagged `ocr-docling`
- **THEN** the docling paperless-gpt instance processes it with Docling OCR
- **AND** the llm paperless-gpt instance does not process it

### Requirement: docling-serve SHALL run as a shared OCI container (not native NixOS service)
docling-serve (`quay.io/docling-project/docling-serve:v1.20.0`) SHALL run as a Podman container rather than a native systemd service, because its transitive dependency `python3.13-docling-parse` is marked broken in nixpkgs. A single shared docling-serve container SHALL serve all paperless-gpt instances.

#### Scenario: Docling-serve container starts with memory constraints
- **WHEN** the docling-serve container is evaluated
- **THEN** it runs with `--memory=1024M` and binds to `127.0.0.1:8070`
- **AND** health checks verify the container is responsive on `/health`
