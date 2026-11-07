"""Builds docs/guide/Alloy-Tester-and-User-Guide.pdf.

    python make_guide.py <screenshots-dir> <output.pdf>

Screenshots come from the app's snapshot mode: ALLOY_SNAPSHOT_DIR=<dir> build/Alloy.app/Contents/MacOS/Alloy
Needs reportlab (which brings Pillow). Uses fonts that ship with macOS (Avenir Next, DIN Condensed).
"""
import os
import sys

from PIL import Image
from reportlab.graphics.shapes import Drawing
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, CondPageBreak, Flowable, Frame, KeepTogether, NextPageTemplate,
                                PageBreak, PageTemplate, Paragraph, Spacer, Table, TableStyle)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SHOTS, OUT = sys.argv[1], sys.argv[2]
LOGO = os.path.join(REPO, "Resources", "AppIcon.png")
VERSION, DATE = "0.9.0", "November 2026"

AVENIR = "/System/Library/Fonts/Avenir Next.ttc"
for name, index in [("Av", 7), ("Av-Medium", 5), ("Av-Demi", 2), ("Av-Bold", 0), ("Av-Heavy", 8), ("Av-Italic", 4)]:
    pdfmetrics.registerFont(TTFont(name, AVENIR, subfontIndex=index))
pdfmetrics.registerFont(TTFont("DIN", "/System/Library/Fonts/Supplemental/DIN Condensed Bold.ttf"))
pdfmetrics.registerFont(TTFont("Sym", "/Library/Fonts/Arial Unicode.ttf"))
pdfmetrics.registerFontFamily("Av", normal="Av", bold="Av-Demi", italic="Av-Italic", boldItalic="Av-Demi")

# Black and white, with blue only where something should stand out.
INK = colors.HexColor("#111111")
INK2 = INK
PAPER = colors.white
CARD = colors.white
EDGE = colors.HexColor("#D9D9D9")
MUTED = colors.HexColor("#666666")
BLUE = colors.HexColor("#2563EB")
# Former accent names, kept so every section call stays the same; all are black now.
COPPER = AMBER = TEAL = PLUM = INK
GREY = colors.HexColor("#F3F3F3")
TINT = {INK: GREY, BLUE: colors.HexColor("#E8EFFD")}

W, H = A4
MARGIN = 19 * mm
TW = W - 2 * MARGIN

S = {
    "body": ParagraphStyle("body", fontName="Av", fontSize=9.8, leading=14.6, spaceAfter=6, textColor=INK),
    "lead": ParagraphStyle("lead", fontName="Av-Medium", fontSize=12.2, leading=17.5, spaceAfter=12, textColor=MUTED),
    "h1": ParagraphStyle("h1", fontName="Av-Heavy", fontSize=27, leading=31, spaceAfter=6, textColor=INK),
    "num": ParagraphStyle("num", fontName="DIN", fontSize=58, leading=52, textColor=COPPER),
    "kicker": ParagraphStyle("kicker", fontName="DIN", fontSize=12, leading=14, textColor=COPPER, spaceAfter=0),
    "h2": ParagraphStyle("h2", fontName="Av-Bold", fontSize=13.5, leading=18, spaceBefore=12, spaceAfter=6, textColor=INK),
    "cardtitle": ParagraphStyle("cardtitle", fontName="Av-Bold", fontSize=10.2, leading=13.5, textColor=INK, spaceAfter=2),
    "cardtext": ParagraphStyle("cardtext", fontName="Av", fontSize=8.7, leading=12.4, textColor=INK),
    "cell": ParagraphStyle("cell", fontName="Av", fontSize=8.4, leading=11.6, textColor=INK),
    "cellb": ParagraphStyle("cellb", fontName="Av-Demi", fontSize=8.4, leading=11.6, textColor=INK),
    "head": ParagraphStyle("head", fontName="Av-Bold", fontSize=8.6, leading=11.6, textColor=colors.white),
    "small": ParagraphStyle("small", fontName="Av", fontSize=7.8, leading=11, textColor=MUTED),
    "caption": ParagraphStyle("caption", fontName="Av-Italic", fontSize=8, leading=11, textColor=MUTED, alignment=TA_CENTER, spaceAfter=10),
    "bullet": ParagraphStyle("bullet", fontName="Av", fontSize=9.8, leading=14.6, leftIndent=14, bulletIndent=1, spaceAfter=3,
                             textColor=INK, bulletColor=COPPER, bulletFontName="Av-Heavy"),
    "stepnum": ParagraphStyle("stepnum", fontName="DIN", fontSize=17, leading=17, textColor=colors.white, alignment=TA_CENTER),
    "statnum": ParagraphStyle("statnum", fontName="DIN", fontSize=30, leading=30, textColor=colors.white),
    "statlabel": ParagraphStyle("statlabel", fontName="Av-Medium", fontSize=8.3, leading=11, textColor=colors.white),
}


def sym(t):
    return f'<font name="Sym">{t}</font>'


def P(text, style="body"):
    return Paragraph(text, S[style])


def bullets(items):
    return [Paragraph(t, S["bullet"], bulletText="■") for t in items]


# ---------------------------------------------------------------- custom flowables

class Badge(Flowable):
    """A filled circle with a number, for steps."""
    def __init__(self, n, color=COPPER, size=7.2 * mm):
        super().__init__()
        self.n, self.color, self.size = n, color, size
        self.width = self.height = size

    def draw(self):
        c = self.canv
        c.setFillColor(self.color)
        c.circle(self.size / 2, self.size / 2, self.size / 2, stroke=0, fill=1)
        c.setFillColor(colors.white)
        c.setFont("DIN", 13)
        c.drawCentredString(self.size / 2, self.size / 2 - 4.3, str(self.n))


def steps(items, color=COPPER):
    rows = [[Badge(i, color), Paragraph(t, S["body"])] for i, t in enumerate(items, 1)]
    t = Table(rows, colWidths=[11 * mm, TW - 11 * mm])
    t.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0),
                           ("RIGHTPADDING", (0, 0), (-1, -1), 0), ("TOPPADDING", (0, 0), (-1, -1), 1),
                           ("BOTTOMPADDING", (0, 0), (-1, -1), 3), ("TOPPADDING", (1, 0), (1, -1), 3)]))
    return t


class Shot(Flowable):
    """A screenshot in a rounded frame with a soft offset shadow."""
    def __init__(self, path, width):
        super().__init__()
        w, h = Image.open(path).size
        self.path, self.width, self.height = path, width, width * h / w

    def wrap(self, aw, ah):
        return self.width, self.height + 3 * mm

    def draw(self):
        c = self.canv
        r = 4 * mm
        c.saveState()
        c.setFillColor(colors.Color(0.11, 0.10, 0.17, alpha=0.16))
        c.roundRect(2.2 * mm, -2.2 * mm + 3 * mm, self.width, self.height, r, stroke=0, fill=1)
        p = c.beginPath()
        p.roundRect(0, 3 * mm, self.width, self.height, r)
        c.clipPath(p, stroke=0, fill=0)
        c.setFillAlpha(1)
        c.drawImage(self.path, 0, 3 * mm, self.width, self.height)
        c.restoreState()


def shot(name, caption, width=132 * mm, stack=None):
    path = os.path.join(SHOTS, name)
    if stack:
        img = Image.open(path)
        parts = [img.crop(b) for b in stack]
        joined = Image.new("RGB", (parts[0].width, sum(p.height for p in parts)), (20, 20, 22))
        y = 0
        for part in parts:
            joined.paste(part, (0, y))
            y += part.height
        path = os.path.join(SHOTS, "stack-" + name)
        joined.save(path)
    frame = Table([[Shot(path, width)]], colWidths=[TW])
    frame.setStyle(TableStyle([("ALIGN", (0, 0), (-1, -1), "CENTER"), ("LEFTPADDING", (0, 0), (-1, -1), 0),
                               ("RIGHTPADDING", (0, 0), (-1, -1), 0), ("TOPPADDING", (0, 0), (-1, -1), 6)]))
    return KeepTogether([frame, Spacer(1, 2), P(caption, "caption")])


def card(title, text, color, width):
    inner = [Paragraph(f'<font color="{color.hexval().replace("0x", "#")}">●</font>  {title}', S["cardtitle"]),
             Paragraph(text, S["cardtext"])]
    t = Table([[inner]], colWidths=[width])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), CARD), ("BOX", (0, 0), (-1, -1), 0.6, EDGE),
                           ("LINEABOVE", (0, 0), (-1, 0), 1.6, color),
                           ("LEFTPADDING", (0, 0), (-1, -1), 9), ("RIGHTPADDING", (0, 0), (-1, -1), 9),
                           ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
                           ("VALIGN", (0, 0), (-1, -1), "TOP")]))
    return t


def card_grid(items, color, cols=2, gap=4 * mm):
    width = (TW - gap * (cols - 1)) / cols
    cells = [card(t, x, color, width) for t, x in items]
    while len(cells) % cols:
        cells.append("")
    rows = [cells[i:i + cols] for i in range(0, len(cells), cols)]
    widths = []
    for i in range(cols):
        widths += [width] + ([gap] if i < cols - 1 else [])
    rows = [sum(([c] + ([""] if i < cols - 1 else []) for i, c in enumerate(r)), []) for r in rows]
    t = Table(rows, colWidths=widths)
    t.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0),
                           ("RIGHTPADDING", (0, 0), (-1, -1), 0), ("TOPPADDING", (0, 0), (-1, -1), 0),
                           ("BOTTOMPADDING", (0, 0), (-1, -1), gap)]))
    return t


def stat_tiles(stats):
    gap = 4 * mm
    width = (TW - gap * (len(stats) - 1)) / len(stats)
    cells, widths = [], []
    for i, (num, label, color) in enumerate(stats):
        tile = Table([[Paragraph(num, S["statnum"])], [Paragraph(label, S["statlabel"])]], colWidths=[width])
        tile.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), color), ("LEFTPADDING", (0, 0), (-1, -1), 9),
                                  ("RIGHTPADDING", (0, 0), (-1, -1), 8), ("TOPPADDING", (0, 0), (0, 0), 11),
                                  ("BOTTOMPADDING", (0, -1), (-1, -1), 10), ("TOPPADDING", (0, 1), (-1, -1), 2),
                                  ("ROUNDEDCORNERS", [3 * mm] * 4)]))
        cells.append(tile)
        widths.append(width)
        if i < len(stats) - 1:
            cells.append("")
            widths.append(gap)
    t = Table([cells], colWidths=widths)
    t.setStyle(TableStyle([("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                           ("VALIGN", (0, 0), (-1, -1), "TOP")]))
    return t


def table(rows, widths, highlight=None, header_color=INK):
    data = []
    for r, row in enumerate(rows):
        data.append([Paragraph(v, S["head"] if r == 0 else ("cellb" if c == 0 else "cell") and S["cellb" if c == 0 else "cell"])
                     for c, v in enumerate(row)])
    t = Table(data, colWidths=widths, repeatRows=1)
    cmds = [("VALIGN", (0, 0), (-1, -1), "TOP"), ("BACKGROUND", (0, 0), (-1, 0), header_color),
            ("BACKGROUND", (0, 1), (-1, -1), CARD),
            ("LEFTPADDING", (0, 0), (-1, -1), 6), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ("LINEBELOW", (0, 1), (-1, -1), 0.5, EDGE), ("ROUNDEDCORNERS", [2.5 * mm] * 4)]
    if highlight is not None:
        cmds += [("BACKGROUND", (highlight, 0), (highlight, 0), BLUE),
                 ("BACKGROUND", (highlight, 1), (highlight, -1), TINT[BLUE])]
    t.setStyle(TableStyle(cmds))
    return t


def callout(text, color=AMBER, title=None):
    content = ([Paragraph(title, S["cardtitle"])] if title else []) + [Paragraph(text, S["body"])]
    t = Table([[content]], colWidths=[TW])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), TINT.get(color, CARD)), ("LINEBEFORE", (0, 0), (0, -1), 4, color),
                           ("LEFTPADDING", (0, 0), (-1, -1), 12), ("RIGHTPADDING", (0, 0), (-1, -1), 12),
                           ("TOPPADDING", (0, 0), (-1, -1), 9), ("BOTTOMPADDING", (0, 0), (-1, -1), 4)]))
    return t


SECTIONS = []


def section(number, kicker, title, lead=None, color=COPPER):
    SECTIONS.append(title)
    num = Paragraph(f'<font color="{color.hexval().replace("0x", "#")}">{number:02d}</font>', S["num"])
    head = [Paragraph(kicker.upper(), ParagraphStyle("k", parent=S["kicker"], textColor=BLUE)), Paragraph(title, S["h1"])]
    t = Table([[num, head]], colWidths=[27 * mm, TW - 27 * mm])
    t.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0),
                           ("RIGHTPADDING", (0, 0), (-1, -1), 0), ("TOPPADDING", (0, 0), (-1, -1), 0),
                           ("TOPPADDING", (1, 0), (1, 0), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 0)]))
    bar = Table([[""]], colWidths=[24 * mm], rowHeights=[1.6 * mm])
    bar.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), color), ("ROUNDEDCORNERS", [0.8 * mm] * 4)]))
    bar.hAlign = "LEFT"
    out = [t, Spacer(1, 8), bar, Spacer(1, 9)]
    if lead:
        out.append(P(lead, "lead"))
    return out


def h2(text, color=COPPER):
    return Paragraph(f'<font color="#2563EB">/</font> {text}', S["h2"])


# ---------------------------------------------------------------- page art

def cover(c, doc):
    c.saveState()
    x = MARGIN
    c.drawImage(LOGO, x - 2 * mm, H - 70 * mm, 30 * mm, 30 * mm, mask="auto")
    c.setFillColor(INK)
    c.setFont("Av-Heavy", 54)
    c.drawString(x, H - 110 * mm, "Alloy")
    c.setFont("Av-Medium", 16)
    c.drawString(x, H - 122 * mm, "Tester and User Guide")
    c.setFillColor(MUTED)
    c.setFont("Av", 12)
    c.drawString(x, H - 131 * mm, "Windows games on your Mac")
    c.setFillColor(BLUE)
    c.setFont("Av-Demi", 12)
    c.drawString(x, H - 146 * mm, "Alloy launches free for every user.")
    c.setStrokeColor(EDGE)
    c.setLineWidth(0.6)
    c.line(x, 24 * mm, W - MARGIN, 24 * mm)
    c.setFillColor(MUTED)
    c.setFont("Av", 9)
    c.drawString(x, 17 * mm, f"Beta {VERSION}  \u00b7  {DATE}")
    c.drawRightString(W - MARGIN, 17 * mm, "For invited testers")
    c.restoreState()


def body_page(c, doc):
    c.saveState()
    c.setFillColor(PAPER)
    c.rect(0, 0, W, H, stroke=0, fill=1)
    c.setStrokeColor(INK)
    c.setLineWidth(0.6)
    c.line(MARGIN, H - 18 * mm, W - MARGIN, H - 18 * mm)
    c.drawImage(LOGO, MARGIN, H - 15.5 * mm, 7 * mm, 7 * mm, mask="auto")
    c.setFillColor(INK)
    c.setFont("DIN", 12)
    c.drawString(MARGIN + 9 * mm, H - 13.4 * mm, "ALLOY")
    c.setFillColor(MUTED)
    c.setFont("DIN", 10)
    c.drawRightString(W - MARGIN, H - 13 * mm, f"TESTER & USER GUIDE  ·  BETA {VERSION}")
    # page number in a black dot
    c.setFillColor(COPPER)
    c.circle(W - MARGIN - 4 * mm, 12 * mm, 4.6 * mm, stroke=0, fill=1)
    c.setFillColor(colors.white)
    c.setFont("DIN", 12)
    c.drawCentredString(W - MARGIN - 4 * mm, 12 * mm - 4.2, str(doc.page))
    c.setFillColor(MUTED)
    c.setFont("Av", 7.5)
    c.drawString(MARGIN, 11 * mm, "For invited testers. Alloy launches free for every user.")
    c.restoreState()


doc = BaseDocTemplate(OUT, pagesize=A4, title="Alloy Tester and User Guide", author="Alloy",
                      subject=f"Alloy beta {VERSION}")
frame = Frame(MARGIN, 22 * mm, TW, H - 46 * mm, id="body", leftPadding=0, rightPadding=0, topPadding=0)
doc.addPageTemplates([PageTemplate("cover", [Frame(0, 0, W, H)], onPage=cover),
                      PageTemplate("body", [frame], onPage=body_page)])

story = [NextPageTemplate("body"), PageBreak()]

# ---------------------------------------------------------------- 1 welcome
story += section(1, "Welcome", "Thanks for testing Alloy",
                 "Alloy plays Windows games on Apple silicon Macs, and it will launch free for every user: "
                 "no trial, no paid tier. You're using beta " + VERSION + " before release.")
story += [P("Alloy sets each game up for you. It reads the game's files, picks the graphics engine that suits it, "
            "turns on the faster options your Mac supports, keeps compiled shaders between plays, and explains "
            "crashes in plain English with a button that fixes them. Under the hood it uses Wine, the open-source "
            "Windows compatibility layer, with Apple's Metal graphics."),
          P("We need three things from you: which of your games run, how well they run, and where Alloy gets in "
            "your way. Section 7 shows what to test and how to report it."),
          Spacer(1, 8),
          stat_tiles([("FREE", "for every user at launch", BLUE),
                      ("3–5×", "faster thread wake-ups with MSync", TEAL),
                      ("11–21 ms", "worst frame once shaders are cached", PLUM),
                      ("120 Hz", "kept on ProMotion displays", INK2)]),
          Spacer(1, 12)]
story.append(card_grid([
    ("Runs on", "Apple silicon Macs (M1 or later) with macOS 14 or later."),
    ("Plays", "Windows games you own: installed folders, setup files, or stores such as Steam and Epic."),
    ("Graphics", "DirectX 10 and 11 through DXMT. DirectX 12 through Apple's D3DMetal, which you add yourself."),
    ("Privacy", "No store passwords, no uploads. Logs stay on your Mac with passwords and tokens removed."),
], TEAL))
story.append(callout("Please test only with games you own legally. Alloy never asks for your Steam, Epic or Apple "
                     "passwords; sign in to stores inside their own apps.", COPPER, "Play fair"))

# ---------------------------------------------------------------- 2 install
story += [PageBreak()] + section(2, "Get set up", "Install Alloy", "A few minutes, most of it one download.", TEAL)
story.append(card_grid([
    ("Mac", "Apple silicon (M1 or later) on macOS 14 or later. 16 GB of memory is comfortable for recent games."),
    ("Rosetta 2", "Alloy's welcome guide installs it if your Mac doesn't have it yet."),
    ("Space", "About 2 GB for Alloy and its game engine (the engine is 1.4 GB), plus your games."),
    ("Internet", "Needed for setup and store downloads."),
], TEAL))
story.append(h2("Install and open Alloy", TEAL))
story.append(steps(["Double-click <b>Alloy-0.9.0.zip</b> to unzip it, then drag <b>Alloy</b> into your "
                    "<b>Applications</b> folder.",
                    "Double-click Alloy. The first time, macOS says it can't check Alloy for malicious software "
                    "and won't open it. Click <b>Done</b>, not Move to Trash.",
                    "Open <b>System Settings \u203a Privacy &amp; Security</b> and scroll down to <b>Security</b>. "
                    "Next to the message that Alloy was blocked, click <b>Open Anyway</b>, then confirm with your "
                    "password or Touch ID and click <b>Open</b>.",
                    "Alloy opens. You only do this once; after that it opens like any other app.",
                    "In the welcome guide, accept the terms and click <b>Install Everything</b>. It installs "
                    "Rosetta 2 if needed, the <b>Alloy Game Engine</b>, and the Windows components games commonly "
                    "need. When it says <b>Ready</b>, you can add games."], TEAL))
story.append(callout("This beta isn't signed with an Apple Developer ID yet, so macOS can't confirm who made it and "
                     "shows an unknown developer warning. Right-clicking and choosing Open no longer gets past it "
                     "on recent macOS; use Open Anyway in System Settings as above. Only do this for a copy of "
                     "Alloy you got directly from the Alloy team.", BLUE, "Why macOS warns you"))

# ---------------------------------------------------------------- 3 user guide
story += [PageBreak()] + section(3, "User guide", "How to use Alloy",
                                 "Three areas in the sidebar: Games, Setup and Advanced. Most people only need Games.")
story.append(h2("Add a game you already have"))
story.append(steps(["Go to <b>Games</b>, click <b>Add Game</b> and choose <b>Add Installed Game Folder…</b> "
                    "You can also drag the folder onto the Games page.",
                    "Alloy finds the game's program and works out the graphics engine and Windows components it "
                    "needs. Nothing runs yet.",
                    "Open the game's page and click <b>Play</b>. Alloy asks you to confirm the first start."]))
story.append(h2("Install a game from its setup file"))
story.append(P("Choose <b>Add Game › Install from Setup File…</b> and pick the game's setup <b>.exe</b> or "
               "<b>.msi</b>. Alloy runs the installer in a new environment and adds the game to your library."))
story.append(h2("Install a game from Steam or Epic"))
story.append(steps(["In <b>Setup</b>, install Steam or the Epic Games Launcher (EA app, Ubisoft Connect, GOG Galaxy and "
                    "Battle.net are there too). Sign in inside the store's own window.",
                    "Choose <b>Add Game › Install from Steam or Epic…</b>",
                    "Paste the game's store link or Steam app ID, for example store.steampowered.com/app/620 or 620.",
                    "The store opens at the game. Click <b>Install</b> there; the store checks that you own it.",
                    "Progress shows at the top of your library, and the game joins it when done. Games you install "
                    "inside a store directly also appear and start through that store."]))
story.append(shot("store-game.png", "Paste a store link or a Steam app ID.", width=100 * mm))

story.append(KeepTogether([h2("Pick a graphics mode"), P("Each game page has one graphics choice:"), card_grid([
    ("Balanced  ·  default", "As smooth as your display allows, capped at its refresh rate for even frame pacing."),
    ("Sharp", "Apple MetalFX upscales every frame to your Retina resolution. Pair it with a lower in-game resolution for more FPS."),
    ("Battery Saver", "Caps the game at 60 FPS for longer battery and a cooler Mac. Shown on displays faster than 60 Hz."),
    ("Compatibility mode", "Wine's own OpenGL graphics. Slower; use it only if a game won't start or draws incorrectly."),
], AMBER)]))
story.append(shot("game.png", "A game page: Play, and the graphics modes.", width=118 * mm,
                  stack=[(444, 130, 2000, 615), (444, 845, 2000, 1340)]))
story.append(KeepTogether([h2("Upscaling and frame generation")] + bullets(["<b>DLSS games:</b> Alloy turns on DLSS to MetalFX automatically. Choose DLSS in the game's own "
                  "settings and the game uses Apple MetalFX instead.",
                  "<b>DLSS Frame Generation games (DirectX 12):</b> with D3DMetal 4 added, the game page offers frame "
                  "generation. Turn on DLSS Frame Generation in the game.",
                  "<b>AMD FSR games:</b> use the game's own FSR setting.",
                  "Other games don't get frame generation: without the game's motion data, made-up frames smear edges "
                  "and add input delay."])))
story.append(h2("Watch and measure performance"))
story += bullets([f"Press <b>{sym('⌥⌘')}M</b> while a game runs to show or hide Apple's performance overlay "
                  "(FPS, frame time, memory). It works even with the game in front.",
                  "<b>Advanced › Performance</b> keeps a benchmark history per game with average FPS, 1% lows and "
                  "stutter counts, imports PresentMon or MangoHud logs, and recommends the best setting."])
story.append(h2("When something goes wrong"))
story += bullets(["A crash or failed start shows <b>What went wrong</b> on the game's page: the cause in plain English "
                  "and a fix button. More options sit under <b>More Fixes</b>.",
                  "<b>Advanced › Diagnostics</b> shows each game's last result, problems and log. "
                  "<b>Open Logs Folder</b> shows the files.",
                  "A frozen game: open its page and click <b>Stop</b>."])
story.append(h2("Remove a game"))
story.append(P("Open the game page's <b>…</b> menu and choose <b>Remove from Alloy…</b>. Only the library "
               "entry goes; your game files are never touched."))
story.append(KeepTogether([h2("DirectX 12 games"), steps(["Download Apple's Game Porting Toolkit from developer.apple.com (free Apple account).",
                    "Open its <b>Evaluation environment</b> disk image and accept Apple's licence.",
                    "In Alloy's <b>Setup</b>, click <b>Add D3DMetal…</b> and choose the mounted volume."], PLUM),
    P("Apple's licence doesn't allow D3DMetal to be redistributed, so Alloy never includes it.", "small")]))
story.append(shot("setup.png", "Setup: game engine, Windows components and DirectX 12 support.", width=66 * mm))
# ---------------------------------------------------------------- 4 features
story += [PageBreak()] + section(4, "What's inside", "Features",
                                 "All of it is in the build you're testing. Figures: Alloy's test programs, M4 MacBook Pro.", PLUM)
story.append(h2("Setup and library", TEAL))
story.append(card_grid([
    ("Automatic game setup", "Reads the game's files and picks DXMT for DirectX 10/11, D3DMetal for DirectX 12, or Compatibility mode for older games."),
    ("Windows components", "Installs what each game needs, such as Visual C++ and .NET support, checked against the publisher's checksum."),
    ("Six game stores", "Steam, Epic, EA app, Ubisoft Connect, GOG Galaxy and Battle.net from Setup. Steam and Epic games install from a link."),
    ("Fast starts", "Each game is scanned once, and again only when its program changes: about 0.5 s saved per visit and launch."),
    ("Game Mode", "Games start as macOS games, so macOS turns on Game Mode for them."),
    ("Videos in games", "MP4/H.264 videos play, including Unreal Engine menu backgrounds and cutscenes."),
], TEAL, cols=3))
story.append(h2("Smoothness and image quality", COPPER))
story.append(card_grid([
    ("Display-matched frame cap", "Even pacing at your display's refresh rate. ProMotion MacBook Pros stay at 120 Hz even when a game asks for 60 Hz."),
    ("DLSS to MetalFX", "Games that ship NVIDIA DLSS use Apple MetalFX upscaling instead, switched on automatically."),
    ("MetalFX frame generation", "For DLSS Frame Generation games on DirectX 12, through D3DMetal 4, from the game's own motion data."),
    ("Protected shader cache", "Shaders live in Alloy's folder, safe from macOS clean-ups. Worst frame: 47–69 ms first play, 11–21 ms after."),
    ("MSync", "On by default: thread wake-ups 3–5× faster, locks about 20×. Matches Steam's setting so games still start."),
    ("Cursor stays hidden", "The Mac cursor no longer pops up over a game that hid it."),
], COPPER, cols=3))
story.append(KeepTogether([h2("Help and privacy", PLUM), card_grid([
    ("Plain-English crash help", "Names the cause (CPU feature, memory, graphics, missing files, store not running) and ranks the fixes."),
    ("No stuck crash windows", "Wine's technical crash window is off, so a crashed game closes within seconds."),
    ("Performance overlay", f"{sym('⌥⌘')}M shows FPS, frame time and memory in any game."),
    ("Control and privacy", "No game starts without your click. No store sign-ins, no uploads; logs stay local and redacted."),
], PLUM, cols=4)]))

# ---------------------------------------------------------------- 5 comparison
story += [PageBreak()] + section(5, "The landscape", "How Alloy compares",
                                 "Alloy wins on price, automatic setup and help when things break, not raw speed. "
                                 "Every app here builds on Wine, Rosetta 2 and Apple Metal.", AMBER)
cw = [28 * mm] + [(TW - 28 * mm) / 5] * 5
story.append(table([
    ["", "Alloy", "CrossOver", "Sikarugir (was Kegworks)", "Whisky", "Game Porting Toolkit"],
    ["Price", "<b>Free</b>", "Paid; 14-day trial", "Free", "Free", "Free"],
    ["Status", "In beta, launching free", "Maintained (commercial)", "Maintained", "Archived May 2025; no longer maintained", "Maintained by Apple"],
    ["Made for", "Players", "Players and businesses", "Enthusiasts building app wrappers", "Players", "Developers evaluating ports"],
    ["How you use it", "Mac app with a game library", "Mac app with bottles", "Wrapper creator", "Mac app with bottles", "Terminal commands"],
    ["Picks graphics per game", "Yes, from the game's own files", "Yes, from CodeWeavers' database (Auto)", "Manual toggles", "Manual", "Manual"],
    ["DirectX 10/11", "DXMT, D3DMetal or OpenGL", "DXMT, D3DMetal, DXVK or OpenGL", "OpenGL by default; D3DMetal optional", "D3DMetal", "D3DMetal"],
    ["DirectX 12", "D3DMetal (you add it)", "D3DMetal (included)", "D3DMetal (optional)", "D3DMetal", "D3DMetal"],
    ["MSync", "On by default", "Per bottle", "—", "—", "—"],
    ["DLSS to MetalFX", "Automatic when the game ships DLSS", "—", "—", "—", "—"],
    ["Crash help", "Plain-English cause and fix buttons", "Logs and support site", "Logs", "Logs", "Logs"],
    ["Store installs", "Six stores from Setup; Steam and Epic games from a link", "Steam and others via install recipes", "Manual", "—", "Manual"],
], cw, highlight=1))
story.append(Spacer(1, 4))
story.append(P("— means the sources we checked don't document it, not that the app lacks it. CrossOver's store page "
               "lists a $34 12-month renewal and a $494 lifetime licence. Competitor details as of November 2026.", "small"))
story.append(KeepTogether([h2("Why it matters to you", AMBER), card_grid([
    ("Free, no trial clock", "CrossOver is polished but paid after 14 days. Whisky is free but archived, so new macOS versions and games may break it."),
    ("Nothing to tune", "Alloy picks the engine, turns on DLSS to MetalFX and MSync, and matches your display. Others leave this to you."),
    ("Fixes, not log files", "A crash comes with a plain-English reason and the fix that fits that game."),
    ("Honest about speed", "Same engine, same settings, about the same FPS anywhere. We'll publish speed comparisons only after measuring."),
], AMBER)]))
story.append(callout("Cloud gaming (GeForce NOW, Xbox Cloud Gaming) streams games from Windows PCs and is the realistic "
                     "way to play titles with kernel anti-cheat on a Mac. Virtual machines such as Parallels run "
                     "Windows for ARM, which many anti-cheat systems refuse.", TEAL, "Also worth knowing"))

# ---------------------------------------------------------------- 6 limits
story += [Spacer(1, 10), CondPageBreak(115 * mm)] + section(6, "Be aware", "Known limits",
                                 "Some games won't run, and a few features haven't met a real game yet.", COPPER)
story.append(table([
    ["Limit", "What it means for you"],
    ["Kernel anti-cheat", "Riot Vanguard, FACEIT, EA Javelin, Ricochet, and the kernel parts of Easy Anti-Cheat and BattlEye block online play. They need a Windows kernel driver, which neither Wine nor macOS can provide."],
    ["DirectX 12", "Needs D3DMetal from Apple's Game Porting Toolkit, added by you. 64-bit games only."],
    ["Not yet tried with a real game", "MetalFX frame generation (no DLSS Frame Generation game was available) and Steam or Epic installs end to end (stores were blocked on the development network)."],
    ["Games with DirectX 11 and 12", "Set up on DXMT. If such a game picks DirectX 12 itself, it may not start. Please report it."],
    ["First play", "Shaders are prepared the first time, so expect some stutter in the first minutes."],
    ["Other stores", "EA app, Ubisoft Connect, GOG Galaxy and Battle.net install from Setup but haven't been tested further."],
    ["Intel Macs, older macOS", "Not supported: Alloy needs Apple silicon and macOS 14 or later."],
], [42 * mm, TW - 42 * mm], header_color=INK2))

# ---------------------------------------------------------------- 7 testing
story += [Spacer(1, 6), CondPageBreak(160 * mm)] + section(7, "Your part", "What to test and how to report it",
                                                          "Play your own games normally, then tell us what worked "
                                                          "and what didn't.", TEAL)
check = ParagraphStyle("check", parent=S["body"], leftIndent=16, bulletIndent=0, bulletFontName="Sym",
                       bulletColor=TEAL, bulletFontSize=11, spaceAfter=4)
tests = [Paragraph(t, check, bulletText="☐") for t in [
    "Install Alloy and the Alloy Game Engine",
    "Add a game you own, and install one through Steam or Epic",
    "Play 30 minutes in each graphics mode the game offers",
    "A DLSS game, with DLSS on in its settings",
    "A DLSS Frame Generation game, if you own one and added D3DMetal",
    "Any crash: did What went wrong explain it, and did the fix help?",
    "Anything confusing in the app, however small"]]
report = [Paragraph(t, check, bulletText=f"{i}") for i, t in enumerate([
    "The game, and where you bought it",
    "Your Mac model, memory and macOS version",
    "The graphics engine and mode on the game's page",
    "What happened, and steps to make it happen again",
    "Optional: the log from <b>Advanced › Diagnostics › Open Logs Folder</b>. Passwords and tokens are "
    "removed; read it before sending, as it may contain folder names."], 1)]
for p in report:
    p.style = ParagraphStyle("rep", parent=check, bulletFontName="DIN", bulletColor=COPPER, bulletFontSize=12)
half = (TW - 6 * mm) / 2
colA = Table([[Paragraph("Test checklist", S["cardtitle"])]] + [[t] for t in tests], colWidths=[half])
colB = Table([[Paragraph("Put in every report", S["cardtitle"])]] + [[r] for r in report], colWidths=[half])
for col, color in ((colA, TEAL), (colB, COPPER)):
    col.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), CARD), ("BOX", (0, 0), (-1, -1), 0.6, EDGE),
                             ("LINEABOVE", (0, 0), (-1, 0), 2.4, color), ("LEFTPADDING", (0, 0), (-1, -1), 10),
                             ("RIGHTPADDING", (0, 0), (-1, -1), 10), ("TOPPADDING", (0, 0), (-1, -1), 1),
                             ("TOPPADDING", (0, 0), (-1, 0), 9), ("BOTTOMPADDING", (0, -1), (-1, -1), 8)]))
two = Table([[colA, "", colB]], colWidths=[half, 6 * mm, half])
two.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 0),
                         ("RIGHTPADDING", (0, 0), (-1, -1), 0)]))
story += [two, Spacer(1, 10),
          callout("To be confirmed by the Alloy team before the beta starts.", BLUE, "Where to send reports")]

# ---------------------------------------------------------------- sources
story += [Spacer(1, 12), h2("Sources", MUTED)]
for name, url in [
    ("CodeWeavers store: CrossOver prices and trial", "https://www.codeweavers.com/store"),
    ("CodeWeavers: Advanced settings in CrossOver Mac 25 (MSync, graphics Auto)", "https://support.codeweavers.com/en_US/advanced-settings-in-crossover-mac"),
    ("It's FOSS: CrossOver 25 release (DXMT, D3DMetal)", "https://itsfoss.com/news/crossover-25-release/"),
    ("Whisky on GitHub: maintenance notice, archived May 11, 2025", "https://github.com/Whisky-App/Whisky"),
    ("Sikarugir on GitHub: successor to Kegworks", "https://github.com/Sikarugir-App/Sikarugir"),
    ("Alloy measurements: docs/COMPATIBILITY.md in the Alloy repository", ""),
]:
    link = f' — <link href="{url}"><font color="#2563EB">{url}</font></link>' if url else ""
    story.append(P(name + link, "small"))
    story.append(Spacer(1, 2))

doc.build(story)
print("wrote", OUT)
