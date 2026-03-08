"""Tests for the frontend formatResponse logic, reimplemented in Python.

The JS formatResponse function applies these transforms in order:
1. HTML-escape the text
2. Convert triple-backtick fenced code blocks to <pre><code>
3. Convert `code` backticks to <code>code</code>
4. Convert **bold** to <strong>bold</strong>
5. Convert newlines to <br> (but not inside <pre> blocks)

These tests verify the same logic using Python's html.escape and regex,
matching the JS implementation in chat.html.
"""
import html
import re
import unittest


def format_response(text: str) -> str:
    """Python equivalent of the JS formatResponse function."""
    s = html.escape(text, quote=False)
    # Triple-backtick fenced code blocks → <pre><code> (BEFORE single backticks)
    s = re.sub(
        r"```\w*\n(.*?)```",
        lambda m: "<pre><code>" + m.group(1) + "</code></pre>",
        s,
        flags=re.DOTALL,
    )
    # Apply inline formatting (backticks, bold, newlines) only OUTSIDE <pre> blocks
    parts = re.split(r"(<pre><code>.*?</code></pre>)", s, flags=re.DOTALL)
    s = "".join(
        part if part.startswith("<pre>") else _format_inline(part)
        for part in parts
    )
    return s


def _format_inline(s: str) -> str:
    """Apply inline formatting to text outside <pre> blocks."""
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = s.replace("\n", "<br>")
    return s


class TestFormatResponseEscaping(unittest.TestCase):
    """Test HTML escaping."""

    def test_html_entities_escaped(self):
        result = format_response('<script>alert("xss")</script>')
        self.assertNotIn("<script>", result)
        self.assertIn("&lt;script&gt;", result)

    def test_ampersand_escaped(self):
        self.assertIn("&amp;", format_response("a & b"))


class TestFormatResponseBackticks(unittest.TestCase):
    """Test backtick → <code> conversion."""

    def test_single_code_span(self):
        self.assertEqual(
            format_response("Use `foo()` here"),
            "Use <code>foo()</code> here",
        )

    def test_multiple_code_spans(self):
        result = format_response("`a` and `b`")
        self.assertEqual(result, "<code>a</code> and <code>b</code>")

    def test_html_inside_backticks_is_escaped(self):
        result = format_response("Use `<div>` tag")
        self.assertEqual(result, "Use <code>&lt;div&gt;</code> tag")


class TestFormatResponseBold(unittest.TestCase):
    """Test **bold** → <strong> conversion."""

    def test_bold_text(self):
        self.assertEqual(
            format_response("This is **important** info"),
            "This is <strong>important</strong> info",
        )


class TestFormatResponseNewlines(unittest.TestCase):
    """Test newline → <br> conversion."""

    def test_newlines(self):
        self.assertEqual(
            format_response("line1\nline2\nline3"),
            "line1<br>line2<br>line3",
        )


class TestFormatResponseTripleBackticks(unittest.TestCase):
    """Test triple-backtick fenced code blocks → <pre><code>."""

    def test_fenced_code_block(self):
        text = "Here:\n```\nprint('hi')\n```\nDone."
        result = format_response(text)
        self.assertIn("<pre><code>print('hi')\n</code></pre>", result)
        self.assertNotIn("```", result)

    def test_fenced_code_block_with_language(self):
        text = "Code:\n```python\nx = 1\n```"
        result = format_response(text)
        self.assertIn("<pre><code>x = 1\n</code></pre>", result)
        self.assertNotIn("```", result)
        self.assertNotIn("python", result)

    def test_fenced_block_preserves_newlines(self):
        """Newlines inside <pre> blocks should NOT become <br>."""
        text = "```\nline1\nline2\n```"
        result = format_response(text)
        self.assertIn("<pre><code>line1\nline2\n</code></pre>", result)
        self.assertNotIn("<br>", result.split("<pre>")[1].split("</pre>")[0])

    def test_fenced_block_before_single_backticks(self):
        """Triple backticks processed first; single backticks inside not matched."""
        text = "```\nuse `foo` here\n```"
        result = format_response(text)
        # Inside <pre>, backticks should NOT become <code>
        self.assertIn("use `foo` here", result)
        self.assertNotIn("<code>foo</code>", result)

    def test_newlines_outside_pre_still_become_br(self):
        """Newlines outside <pre> blocks should still become <br>."""
        text = "before\n```\ncode\n```\nafter"
        result = format_response(text)
        self.assertTrue(result.startswith("before<br>"))
        self.assertTrue(result.endswith("<br>after"))

    def test_html_inside_fenced_block_is_escaped(self):
        text = '```\n<script>alert("xss")</script>\n```'
        result = format_response(text)
        self.assertNotIn("<script>", result)
        self.assertIn("&lt;script&gt;", result)


class TestFormatResponseCombined(unittest.TestCase):
    """Test all formatting combined."""

    def test_combined(self):
        result = format_response("Run `npm install` for **fast** setup\nDone.")
        self.assertEqual(
            result,
            "Run <code>npm install</code> for <strong>fast</strong> setup<br>Done.",
        )

    def test_plain_text_unchanged(self):
        self.assertEqual(format_response("Hello world"), "Hello world")

    def test_empty_string(self):
        self.assertEqual(format_response(""), "")


if __name__ == "__main__":
    unittest.main()
