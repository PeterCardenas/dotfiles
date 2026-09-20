from __future__ import annotations

import base64
import json
from pathlib import Path
import runpy
import tempfile
import unittest


SLACK_SEARCH = Path(__file__).parents[1] / "bin" / "executable_slack-search"


class SlackSearchEntrypointTests(unittest.TestCase):
    def test_download_mode_allows_only_slack_file_read(self) -> None:
        module = runpy.run_path(str(SLACK_SEARCH))

        request = module["parse_download_request"](
            ["--download-file", "F123", "--output", "temp/fonts.zip"]
        )

        self.assertEqual(request.file_id, "F123")
        self.assertEqual(request.output, Path("temp/fonts.zip").resolve())
        self.assertEqual(
            module["DOWNLOAD_TOOLS"],
            ("mcp__claude_ai_Slack__slack_read_file",),
        )
        self.assertIn("Return exactly one JSON object", module["build_download_prompt"](request))

    def test_extracts_blob_path_from_delegate_result(self) -> None:
        module = runpy.run_path(str(SLACK_SEARCH))
        stdout = json.dumps(
            {
                "result": json.dumps(
                    {"blob_path": "/tmp/tool-results/slack-font.zip"}
                )
            }
        )

        self.assertEqual(
            module["extract_download_payload"](stdout),
            {"blob_path": "/tmp/tool-results/slack-font.zip"},
        )

    def test_materializes_connector_blob_and_reports_integrity(self) -> None:
        module = runpy.run_path(str(SLACK_SEARCH))
        payload = b"PK\x03\x04font archive"

        with tempfile.TemporaryDirectory() as directory:
            tool_results = Path(directory) / "tool-results"
            tool_results.mkdir()
            source = tool_results / "slack-font.zip"
            output = Path(directory) / "font.zip"
            source.write_bytes(payload)

            result = module["materialize_download"](
                {"blob_path": str(source)}, output
            )

            self.assertEqual(output.read_bytes(), payload)
            self.assertEqual(result["size"], len(payload))
            self.assertEqual(result["signature"], "504b0304")

    def test_materializes_inline_base64_when_connector_does_not_spill_to_disk(self) -> None:
        module = runpy.run_path(str(SLACK_SEARCH))
        payload = b"small file"

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "file.bin"
            module["materialize_download"](
                {"base64_payload": base64.b64encode(payload).decode()}, output
            )

            self.assertEqual(output.read_bytes(), payload)


if __name__ == "__main__":
    unittest.main()
