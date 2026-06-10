---
name: mapping-document-creator
description: Create Markdown or Excel response mapping documents from Java and Spring Boot projects by tracing end-to-end controller flows, service calls, mapper transformations, repository or database calls, response entities, DTOs, status codes, validation annotations, error handlers, and serializers. Use when asked to document API responses, endpoint-to-response mappings, controller-to-service-to-database flow, controller response contracts, DTO field mappings, API response examples, Excel response maps, or Spring Boot response behavior.
---

# Mapping Document Creator

## Mission

Generate an accurate response mapping document for a Java/Spring Boot project. Map each API endpoint to the response shape it returns, including the end-to-end controller flow, service calls, mapper transformations, repository or database calls, HTTP status codes, DTO fields, wrappers, errors, conditional response paths, and source evidence.

Prefer evidence from code over assumptions. When behavior cannot be proven from the repository, mark it as `Unverified`.

Default to Markdown unless the user asks for Excel, spreadsheet, workbook, `.xlsx`, CSV-ready tables, or sheet-based output.

## Read First

- Build files: `pom.xml`, `build.gradle`, or `build.gradle.kts`.
- Controller classes annotated with `@RestController`, `@Controller`, `@RequestMapping`, `@GetMapping`, `@PostMapping`, `@PutMapping`, `@PatchMapping`, or `@DeleteMapping`.
- DTOs, records, response wrappers, model classes, and enum types returned by controllers.
- Service methods called by controllers, including downstream services, mappers, validators, gateways, repositories, and clients.
- Mapper classes or methods that convert entities/domain objects to DTOs, including MapStruct, manual mappers, constructors, builders, and static factories.
- Repository or persistence calls: Spring Data repositories, JPA queries, JDBC templates, entity managers, stored procedure calls, or custom DAO classes.
- Exception handlers: `@ControllerAdvice`, `@RestControllerAdvice`, `@ExceptionHandler`, `ResponseStatusException`, and custom error response classes.
- Serialization and validation annotations: Jackson, Bean Validation, Swagger/OpenAPI, Lombok, Java records, and Kotlin data classes if present.
- Existing API documentation, tests, MockMvc/WebTestClient tests, or OpenAPI specs if available.

## Workflow

1. Identify the Spring Boot module and base package.
2. List all REST controllers and route-level mappings.
3. For each endpoint, trace the end-to-end flow:
   - Controller method.
   - Service methods called directly or indirectly.
   - Mapper or assembler methods that create response DTOs.
   - Repository, DAO, gateway, or database calls used to fetch or mutate data.
   - Domain/entity fields that feed response DTO fields.
4. For each endpoint, resolve:
   - HTTP method and full path.
   - Request parameters, path variables, headers, and request body type.
   - Return type, including `ResponseEntity<T>`, wrappers, generics, `Optional`, collections, streams, pages, maps, and `void`.
   - Success status codes from annotations, `ResponseEntity`, `@ResponseStatus`, and default Spring behavior.
   - Error status codes from exception handlers and explicit thrown exceptions.
5. Follow DTO fields recursively enough to document the external response shape.
6. Resolve field names using Jackson annotations and naming strategies when discoverable.
7. Capture conditional response paths, such as `404` when not found, `204` when no content, validation failures, and business-rule errors.
8. Produce the response mapping document using the requested output mode below.
9. Include source references for every endpoint, flow step, repository call, and major response type.
10. For automated Excel output, run the bundled PowerShell scanner against the Spring Boot project.

## End-To-End Flow Rules

- Trace from controller to service before documenting response fields when the response is assembled outside the controller.
- Include every service method that materially affects the response body, status, headers, or error path.
- Include repository/database calls that determine returned data, not-found behavior, filtering, sorting, pagination, or business decisions.
- Include mapper calls that rename, flatten, enrich, filter, redact, default, or aggregate fields.
- Document external service/gateway/client calls when they affect response fields or status codes.
- Do not over-expand unrelated helper methods; follow only the calls that affect response shape, response status, or response errors.
- When static analysis cannot prove a downstream call, mark the flow step as `Inferred` or `Unverified`.

## Response Shape Rules

- Treat `ResponseEntity<T>` as the authoritative source for explicit status codes and headers.
- Treat controller method return type as the default success response when no `ResponseEntity` is used.
- Treat `void`, `Void`, `ResponseEntity<Void>`, and `Mono<Void>` as no-body responses unless code writes directly to the response.
- Treat `List<T>`, `Set<T>`, arrays, `Page<T>`, and custom collection wrappers as collections and document item shape.
- Treat `Map<String, T>` as an object with dynamic keys unless the keys are fixed by code.
- Treat Java records as DTOs whose canonical constructor components define response fields.
- Treat Lombok DTOs by reading fields plus generated getter/setter intent; do not require generated source.
- Treat enums as string values by default unless custom Jackson serialization proves otherwise.
- Treat `@JsonProperty`, `@JsonAlias`, `@JsonIgnore`, `@JsonInclude`, `@JsonFormat`, `@JsonUnwrapped`, and custom serializers as response-contract modifiers.

## Output Modes

- Use `Markdown Document Contract` when the user asks for a document, Markdown, text output, or does not specify a format.
- Use `Excel Workbook Contract` when the user asks for Excel, spreadsheet, workbook, `.xlsx`, CSV-ready tables, tabs, or sheets.
- If the runtime can create files, create the requested `.xlsx` workbook. If file creation is unavailable, return sheet-ready tables with exact sheet names and columns so the user can paste them into Excel.

## Markdown Document Contract

Create a Markdown document with these sections:

1. `# Response Mapping Document`
2. `## Scope`
   - Project/module reviewed.
   - Packages scanned.
   - Date generated if useful.
   - Known gaps or assumptions.
3. `## Endpoint Summary`
   - Table with method, path, controller method, success status, response type, and error statuses.
4. `## End-To-End Flow`
   - One flow table per endpoint showing controller, service, mapper, repository/database, and external call steps.
5. `## Detailed Response Mapping`
   - One subsection per endpoint.
   - Include route, source method, request inputs, success response body, status codes, headers when known, error responses, and source references.
6. `## DTO Field Catalog`
   - Field-by-field mapping for response DTOs, including JSON name, Java field/type, nullability if inferable, enum values, nested types, and notes.
7. `## Error Response Mapping`
   - Exception or failure source to HTTP status and response body.
8. `## Unverified Or Ambiguous Items`
   - Anything that required inference or could not be proven from code.

## Excel Workbook Contract

Create an `.xlsx` workbook named `response-mapping.xlsx` unless the user provides another name.

Use these sheets:

1. `Scope`
2. `Endpoint Summary`
3. `End To End Flow`
4. `Detailed Mapping`
5. `DTO Field Catalog`
6. `Error Mapping`
7. `Unverified Items`

### Sheet: Scope

Columns:

- `Project Or Module`
- `Packages Scanned`
- `Generated On`
- `Source Root`
- `Known Gaps`
- `Assumptions`

### Sheet: Endpoint Summary

Columns:

- `HTTP Method`
- `Path`
- `Controller Class`
- `Controller Method`
- `Source File`
- `Success Status`
- `Response Type`
- `Collection Or Wrapper`
- `Error Statuses`
- `Notes`

### Sheet: End To End Flow

Use one row per meaningful flow step.

Columns:

- `HTTP Method`
- `Path`
- `Step Order`
- `Layer`
- `Class`
- `Method Or Call`
- `Input`
- `Output`
- `Response Impact`
- `Source File`
- `Verified`
- `Notes`

### Sheet: Detailed Mapping

Use one row per response field per endpoint. For no-body responses, include one row with `Response Body Present` set to `No`.

Columns:

- `HTTP Method`
- `Path`
- `Controller Method`
- `Success Status`
- `Response Type`
- `Response Body Present`
- `JSON Field`
- `Source Field`
- `Java Type`
- `Required`
- `Nested Type`
- `Transformation Source`
- `Repository Or DB Source`
- `Source File`
- `Notes`

### Sheet: DTO Field Catalog

Columns:

- `DTO Name`
- `JSON Field`
- `Source Field`
- `Java Type`
- `Required`
- `Nullable Evidence`
- `Enum Values`
- `Nested Type`
- `Domain Or Entity Source`
- `Jackson Or Validation Annotations`
- `Source File`
- `Notes`

### Sheet: Error Mapping

Columns:

- `HTTP Method`
- `Path`
- `Status`
- `Exception Or Failure Source`
- `Handler`
- `Body Type`
- `Source File`
- `Notes`

### Sheet: Unverified Items

Columns:

- `Area`
- `Endpoint Or Type`
- `Reason`
- `Source File`
- `Recommended Follow-Up`

### Excel Formatting Rules

- Freeze the header row on every sheet when file creation tooling is available.
- Make header rows bold.
- Auto-size columns when supported.
- Use one fact per cell; avoid multi-paragraph content in cells.
- Keep source paths relative to the reviewed project when possible.
- Use `Unverified` in cells where behavior is inferred or not proven.

## Automated Excel Generation

Run the bundled PowerShell scanner from a PowerShell terminal:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "<skill-folder>\scripts\Generate-ResponseMapping.ps1" `
  -ProjectPath "<spring-boot-project>" `
  -OutputPath "<spring-boot-project>\response-mapping.xlsx" `
  -Force
```

The scanner and workbook writer use only PowerShell and built-in .NET ZIP/XML APIs. They do not
require JSON preparation, Python, Java tooling, an MCP server, Microsoft Excel, or third-party
PowerShell modules.

The scanner:

- Finds Java source files while excluding common build and generated-source directories.
- Detects Spring controllers, class-level paths, endpoint mappings, request methods, and return types.
- Traces injected service, mapper, repository, DAO, client, and gateway method calls.
- Reads DTO fields, records, Jackson names, validation annotations, nested types, and enums.
- Resolves explicit response statuses, thrown exceptions, and controller-advice handlers.
- Creates all seven workbook sheets and marks unresolved static-analysis results as `Unverified`.

Use `-TraceDepth` to change recursive call tracing depth. The default is `4`.

Before running:

- Confirm the project contains Java Spring source files.
- Close an existing output workbook before replacing it.
- Use `-Force` only when replacing the previous output is intended.

After running:

- Confirm that `response-mapping.xlsx` opens successfully.
- Confirm that all seven sheets exist.
- Review `Unverified Items` for interfaces, generated code, reflection, runtime wiring, and external dependencies.
- Use the interactive skill analysis to investigate unresolved rows when greater accuracy is required.

## Endpoint Detail Template

Use this shape for each endpoint:

```markdown
### METHOD /path

- Controller: `ClassName.methodName`
- Source: `src/main/java/.../ClassName.java`
- Success status: `200 OK`
- Response type: `ResponseDto`
- End-to-end flow:

| Step | Layer | Class/method | Output | Response impact |
| --- | --- | --- | --- | --- |
| 1 | Controller | `RefundController.evaluate` | calls service | Defines route and status handling |
| 2 | Service | `RefundService.evaluate` | domain decision | Computes eligibility |
| 3 | Repository | `BookingRepository.findById` | `Booking` | Missing booking may lead to `404` |
| 4 | Mapper | `RefundMapper.toDecision` | `RefundDecision` | Maps domain fields to response JSON |

- Response body:

| JSON field | Source field | Type | Required | Notes |
| --- | --- | --- | --- | --- |
| `id` | `id` | `Long` | Yes | Identifier returned by service |

- Error responses:

| Status | Source | Body type | Notes |
| --- | --- | --- | --- |
| `404` | `ResourceNotFoundException` | `ErrorResponse` | Returned when entity is missing |

- Mapping notes:
  - Document transformations from service/domain objects to response DTOs.
  - Mark inferred fields as `Inferred`.
```

## Guardrails

- Do not invent endpoints, fields, statuses, or examples that cannot be traced to code or tests.
- Do not treat database entities as response bodies unless the controller actually returns them.
- Do not assume every exception handler applies globally; check package scope, annotations, and controller advice configuration.
- Do not ignore inherited controller mappings or class-level `@RequestMapping`.
- Do not ignore overloaded methods, generic wrappers, or nested DTOs.
- Do not stop at the controller when services, mappers, repositories, or database calls determine response content.
- Do not describe repository/database calls as response fields; document them as flow/data sources unless the entity is directly returned.
- Do not hide uncertainty. Put uncertain behavior in `Unverified Or Ambiguous Items`.
- Do not change project code unless the user explicitly asks; this skill is for documentation generation.
- Do not create an Excel file when the user explicitly requests Markdown-only output.

## Verification

Before finalizing, check:

- Every controller endpoint appears in `Endpoint Summary`.
- Every endpoint has an end-to-end flow or a clear note explaining why no downstream flow exists.
- Every success response type appears in `DTO Field Catalog`.
- Every documented field has a source field, accessor, record component, or serializer evidence.
- Service, mapper, and repository/database calls that affect the response are represented in the flow.
- Error statuses are tied to explicit code paths or exception handlers.
- The document separates verified facts from inferred behavior.
- Excel output, when requested, includes all required sheets and headers.
