import Testing
@testable import MacDown

@Suite struct MarkdownRendererTests {
    func render(_ md: String) -> String { MarkdownRenderer.html(from: md) }

    @Test func headings() {
        #expect(render("# Hello World") == "<h1 id=\"hello-world\">Hello World</h1>\n")
        #expect(render("Title\n===") == "<h1 id=\"title\">Title</h1>\n")
        #expect(render("## Closed ##") == "<h2 id=\"closed\">Closed</h2>\n")
        #expect(render("#NotAHeading") == "<p>#NotAHeading</p>\n")
    }

    @Test func emphasis() {
        #expect(render("**bold** and *it* and ~~gone~~") == "<p><strong>bold</strong> and <em>it</em> and <del>gone</del></p>\n")
        #expect(render("*a **b** c*") == "<p><em>a <strong>b</strong> c</em></p>\n")
        #expect(render("***both***") == "<p><em><strong>both</strong></em></p>\n")
        #expect(render("snake_case_name") == "<p>snake_case_name</p>\n")
        #expect(render("2 * 3 * 4") == "<p>2 * 3 * 4</p>\n")
    }

    @Test func codeAndEscaping() {
        #expect(render("use `<div>` here") == "<p>use <code>&lt;div&gt;</code> here</p>\n")
        #expect(render("```swift\nlet x = 1 < 2\n```") == "<pre><code class=\"language-swift\">let x = 1 &lt; 2\n</code></pre>\n")
        #expect(render("<script>alert(1)</script>") == "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>\n")
        #expect(render("\\*not em\\*") == "<p>*not em*</p>\n")
        #expect(render("    indented") == "<pre><code>indented\n</code></pre>\n")
    }

    @Test func links() {
        #expect(render("[Apple](https://apple.com \"Home\")") == "<p><a href=\"https://apple.com\" title=\"Home\">Apple</a></p>\n")
        #expect(render("![Logo](img/logo.png)") == "<p><img src=\"img/logo.png\" alt=\"Logo\"></p>\n")
        #expect(render("see https://example.com.") == "<p>see <a href=\"https://example.com\">https://example.com</a>.</p>\n")
        #expect(render("[ref link][r]\n\n[r]: https://x.dev") == "<p><a href=\"https://x.dev\">ref link</a></p>\n")
        #expect(render("[a](javascript:alert(\"x\"))").contains("&quot;"))
    }

    @Test func lists() {
        #expect(render("- one\n- two") == "<ul>\n<li>one</li>\n<li>two</li>\n</ul>\n")
        #expect(render("3. a\n4. b") == "<ol start=\"3\">\n<li>a</li>\n<li>b</li>\n</ol>\n")
        #expect(render("- a\n  - b\n- c") == "<ul>\n<li>a\n<ul>\n<li>b</li>\n</ul>\n</li>\n<li>c</li>\n</ul>\n")
        #expect(render("- [x] done\n- [ ] todo") ==
            "<ul>\n<li class=\"task\"><input type=\"checkbox\" disabled checked> done</li>\n<li class=\"task\"><input type=\"checkbox\" disabled> todo</li>\n</ul>\n")
        #expect(render("- a\n\n- b") == "<ul>\n<li><p>a</p>\n</li>\n<li><p>b</p>\n</li>\n</ul>\n")
        #expect(render("- a\n\nafter") == "<ul>\n<li>a</li>\n</ul>\n<p>after</p>\n")
    }

    @Test func blocks() {
        #expect(render("> quote\n> more") == "<blockquote>\n<p>quote\nmore</p>\n</blockquote>\n")
        #expect(render("a\n\n---\n\nb") == "<p>a</p>\n<hr>\n<p>b</p>\n")
        #expect(render("line one  \nline two") == "<p>line one<br>\nline two</p>\n")
    }

    @Test func tables() {
        let html = render("| A | B |\n|:--|--:|\n| 1 | `x|y` |")
        #expect(html == "<table>\n<thead>\n<tr><th style=\"text-align:left\">A</th><th style=\"text-align:right\">B</th></tr>\n</thead>\n<tbody>\n<tr><td style=\"text-align:left\">1</td><td style=\"text-align:right\"><code>x|y</code></td></tr>\n</tbody>\n</table>\n")
    }
}
