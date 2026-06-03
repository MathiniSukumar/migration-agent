# Java to Kotlin Migration MCP Setup

Use this guide to connect the repo-local Java-to-Kotlin migration MCP server to GitHub Copilot Chat in IntelliJ.

## Project Folder

Open this folder in IntelliJ:

```text
C:\Users\rsent\Desktop\Mathini
```

## Agent Files

Migration skill:

```text
C:\Users\rsent\Desktop\Mathini\.agents\skills\java-to-kotlin-migration\SKILL.md
```

MCP server script:

```text
C:\Users\rsent\Desktop\Mathini\.mcp\java-kotlin-migration\server.ps1
```

Example MCP config:

```text
C:\Users\rsent\Desktop\Mathini\.vscode\mcp.json
```

## IntelliJ Setup Steps

1. Open IntelliJ.
2. Open the project folder:

```text
C:\Users\rsent\Desktop\Mathini
```

3. Open GitHub Copilot Chat.
4. Switch Copilot Chat to Agent mode.
5. Open MCP configuration:

```text
Copilot Chat -> tools icon -> Configure MCP server / Add MCP Tools
```

6. If Copilot opens an `mcp.json` file, add this config:

```json
{
  "servers": {
    "java-kotlin-migration": {
      "type": "stdio",
      "command": "powershell",
      "args": [
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "C:\\Users\\rsent\\Desktop\\Mathini\\.mcp\\java-kotlin-migration\\server.ps1"
      ]
    }
  }
}
```

7. Save the `mcp.json` file.
8. If Copilot asks whether you trust or want to start the server, approve it.

## Test The MCP Server

In Copilot Chat, run:

```text
Use the java-kotlin-migration MCP server.
Call java_kotlin_migration_status for projectPath deadcodescanner-review\deadcodescanner\deadcodescanner.
```

Expected result should include something like:

```text
Main Java files: 26
Test Java files: 1
Main Kotlin files: 0
Build files: 3
```

Then test Maven through MCP:

```text
Use the java-kotlin-migration MCP server.
Run java_kotlin_run_maven for projectPath deadcodescanner-review\deadcodescanner\deadcodescanner with goal test.
```

Expected result:

```text
Exit code: 0
```

## Start Migration

Use this prompt in Copilot Chat:

```text
Use the selected Java-to-Kotlin migration skill and the java-kotlin-migration MCP tools.

For deadcodescanner-review\deadcodescanner\deadcodescanner:
1. Check Kotlin support.
2. If missing, add minimal Maven Kotlin support.
3. Pick one safe Java file.
4. Convert it to Kotlin.
5. Run Maven tests through MCP.
```

## Notes

- IntelliJ does not automatically run `server.ps1` when you open the project.
- Copilot starts `server.ps1` only after MCP is configured and used.
- The MCP server gives Copilot tools for inspection and testing.
- The selected skill gives migration rules and guard rails.
- Migrate one Java file at a time, then run tests.
