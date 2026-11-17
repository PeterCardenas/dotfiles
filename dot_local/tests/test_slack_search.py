from __future__ import annotations

import base64
import json
from pathlib import Path
import runpy
import tempfile
import unittest


SLACK_SEARCH = Path(__file__).parents[1] / "bin" / "executable_slack-search"
READ_FILE_TOOL = "mcp__claude_ai_Slack__slack_read_file"
PNG_BYTES = b"\x89PNG\r\n\x1a\n" + (2000).to_bytes(4, "big") + (840).to_bytes(4, "big")


def _stream(*tool_result_blocks: dict[str, object], is_error: bool = False) -> str:
    """Build the claude stream-json events emitted around one slack_read_file call."""
    events = [
        {
            "type": "assistant",
            "message": {
                "content": [
                    {"type": "tool_use", "id": "toolu_1", "name": READ_FILE_TOOL, "input": {}}
                ]
            },
        },
        {
            "type": "user",
            "message": {
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_1",
                        "is_error": is_error,
                        "content": list(tool_result_blocks),
                    }
                ]
            },
        },
        {"type": "result", "is_error": False, "result": "DONE"},
    ]
    return "\n".join(json.dumps(event) for event in events)


def _metadata_block(mime_type: str) -> dict[str, object]:
    return {
        "type": "text",
        "text": f"File ID: F1\nTitle: shot.png\nMIME Type: {mime_type}\nSize: 709.0 KB\n",
    }


class SlackSearchEntrypointTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = runpy.run_path(str(SLACK_SEARCH))

    def test_download_mode_allows_only_slack_file_read(self) -> None:
        request = self.module["parse_download_request"](
            ["--download-file", "F123", "--output", "temp/fonts.zip"]
        )

        self.assertEqual(request.file_id, "F123")
        self.assertEqual(request.output, Path("temp/fonts.zip").resolve())
        self.assertEqual(self.module["DOWNLOAD_TOOLS"], (READ_FILE_TOOL,))

    def test_download_prompt_does_not_ask_model_to_transcribe_payload(self) -> None:
        request = self.module["parse_download_request"](
            ["--download-file", "F123", "--output", "out.bin"]
        )

        prompt = self.module["build_download_prompt"](request)

        self.assertIn("F123", prompt)
        self.assertNotIn("base64", prompt)
        self.assertNotIn("blob_path", prompt)

    def test_extracts_blob_path_from_tool_result_text(self) -> None:
        stream = _stream(
            _metadata_block("application/pdf"),
            {
                "type": "text",
                "text": "[Resource from claude.ai Slack at slack-file://F1] Binary content "
                "(application/pdf, 259.2KB) saved to /tmp/x/tool-results/mcp-blob-1.pdf",
            },
        )

        payload = self.module["extract_download_payload"](stream)

        self.assertEqual(payload.blob_path, "/tmp/x/tool-results/mcp-blob-1.pdf")
        self.assertIsNone(payload.inline_base64)
        self.assertEqual(payload.mime_type, "application/pdf")

    def test_extracts_inline_image_block_regression(self) -> None:
        # Regression: PNG screenshots come back as an MCP image block, which the
        # model cannot transcribe, so downloads failed with "exactly one supported source".
        encoded = base64.b64encode(PNG_BYTES).decode()
        stream = _stream(
            _metadata_block("image/png"),
            {
                "type": "image",
                "source": {"type": "base64", "media_type": "image/png", "data": encoded},
            },
        )

        payload = self.module["extract_download_payload"](stream)

        self.assertEqual(payload.inline_base64, encoded)
        self.assertIsNone(payload.blob_path)
        self.assertEqual(payload.mime_type, "image/png")

    def test_extracts_inline_document_block(self) -> None:
        encoded = base64.b64encode(b"%PDF-1.7").decode()
        stream = _stream(
            {
                "type": "document",
                "source": {"type": "base64", "media_type": "application/pdf", "data": encoded},
            }
        )

        self.assertEqual(self.module["extract_download_payload"](stream).inline_base64, encoded)

    def test_rejects_tool_error_with_connector_message(self) -> None:
        stream = _stream({"type": "text", "text": "file_not_found"}, is_error=True)

        with self.assertRaisesRegex(ValueError, "file_not_found"):
            self.module["extract_download_payload"](stream)

    def test_rejects_result_without_file_content(self) -> None:
        stream = _stream(_metadata_block("image/png"))

        with self.assertRaisesRegex(ValueError, "no file content"):
            self.module["extract_download_payload"](stream)

    def test_rejects_ambiguous_result_with_multiple_sources(self) -> None:
        encoded = base64.b64encode(PNG_BYTES).decode()
        image = {"type": "image", "source": {"type": "base64", "data": encoded}}
        stream = _stream(image, image)

        with self.assertRaisesRegex(ValueError, "2 file sources"):
            self.module["extract_download_payload"](stream)

    def test_rejects_stream_without_read_file_call(self) -> None:
        stream = json.dumps({"type": "result", "is_error": False, "result": "I could not"})

        with self.assertRaisesRegex(ValueError, "never returned a slack_read_file result"):
            self.module["extract_download_payload"](stream)

    def test_materializes_connector_blob_and_reports_integrity(self) -> None:
        payload_bytes = b"PK\x03\x04font archive"
        with tempfile.TemporaryDirectory() as directory:
            tool_results = Path(directory) / "tool-results"
            tool_results.mkdir()
            source = tool_results / "slack-font.zip"
            output = Path(directory) / "font.zip"
            source.write_bytes(payload_bytes)

            result = self.module["materialize_download"](
                self.module["DownloadPayload"](
                    blob_path=str(source), inline_base64=None, mime_type="application/zip"
                ),
                output,
            )

            self.assertEqual(output.read_bytes(), payload_bytes)
            self.assertEqual(result["size"], len(payload_bytes))
            self.assertEqual(result["signature"], "504b0304")
            self.assertEqual(result["source"], "blob")

    def test_materializes_inline_image_and_flags_possible_resize(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "shot.png"

            result = self.module["materialize_download"](
                self.module["DownloadPayload"](
                    blob_path=None,
                    inline_base64=base64.b64encode(PNG_BYTES).decode(),
                    mime_type="image/png",
                ),
                output,
            )

            self.assertEqual(output.read_bytes(), PNG_BYTES)
            self.assertEqual(result["source"], "inline")
            self.assertEqual(result["mime_type"], "image/png")
            self.assertIn("resized", str(result["note"]))


if __name__ == "__main__":
    unittest.main()
