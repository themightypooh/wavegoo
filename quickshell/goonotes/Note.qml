// One sticky note: a layer-shell surface on the desktop (below windows, or above them when pinned).
// Drawn as Amiga AGA pixel art like the file cabinet: dithered paper with a folded corner and a
// coloured header; the goo level rises up the paper with how much you've written.
import QtQuick
import Quickshell
import QtQuick.Shapes
import Quickshell.Wayland

PanelWindow {
    id: win
    required property string modelData
    required property var app
    readonly property string nid: modelData
    readonly property var d: app.store[nid] || ({})

    // live state, seeded once from the store
    property int px: d.x ?? 120
    property int py: d.y ?? 120
    property int pw: d.w ?? 300
    property int ph: d.h ?? 280
    property int ci: d.color ?? 0
    property bool pinned: !!d.pinned
    readonly property var pal: app.palette[ci % app.palette.length]

    readonly property real goo: Math.min(1, body.length / app.gooFull)
    property real gooShown: goo
    Behavior on gooShown { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
    property real t: 0
    property bool armed: false   // trash clicked once
    property bool raised: false  // lifted above windows for a moment after picking it in the drawer
    property bool picking: false // category menu open
    readonly property string cat: { app.rev; return (app.store[nid] || {}).category || "" }

    screen: app.screenFor(d.screen || "")
    visible: app.shown
    color: "transparent"
    anchors { top: true; left: true }
    margins { top: win.py; left: win.px }
    implicitWidth: win.pw
    implicitHeight: win.ph
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "goonotes"
    WlrLayershell.layer: win.pinned || win.raised || app.peek ? WlrLayer.Top : WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Connections {
        target: win.app
        function onPinEverything(on) { win.pinned = on; win.app.update(win.nid, { pinned: on }) }
        function onFlash(id) { if (id === win.nid) win.lift() }
        // edited on the phone: show it (never while you're typing here; the sync waits for that)
        function onRemoteEdit(id) { if (id === win.nid && !edit.activeFocus) { edit.text = win.d.text || ""; win.ci = win.d.color || 0 } }
    }
    Component.onCompleted: {
        edit.text = d.text || ""
        if (app.pendingFlash === nid) { app.pendingFlash = ""; lift() }
    }
    // Switching layers on a window that hasn't finished appearing makes it vanish, so a brand-new
    // note waits a moment before it's lifted
    readonly property real born: Date.now()
    function lift() {
        if (Date.now() - born < 400) { liftSoon.restart(); return }
        raised = true; raiseTimer.interval = 20000; raiseTimer.restart(); pulse.restart()
    }
    Timer { id: liftSoon; interval: 400; onTriggered: win.lift() }
    // clicked away after typing: sink back to the desktop shortly after
    Connections {
        target: edit
        function onActiveFocusChanged() { if (!edit.activeFocus && win.raised) { raiseTimer.interval = 1500; raiseTimer.restart() } }
    }
    // stays up while you're typing in it or pointing at it, then sinks back to the desktop
    Timer { id: raiseTimer; interval: 20000; onTriggered: if (edit.activeFocus || hover.hovered) restart(); else win.raised = false }
    property real glow: 0
    SequentialAnimation {
        id: pulse
        NumberAnimation { target: win; property: "glow"; from: 0; to: 1; duration: 180 }
        NumberAnimation { target: win; property: "glow"; to: 0; duration: 1400; easing.type: Easing.InQuad }
    }

    readonly property int headerH: 34
    readonly property int pitch: 9

    function mix(f) {
        const a = Qt.color(pal.a), b = Qt.color(pal.b)
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, 1)
    }

    // the wave only moves while you're on the note; otherwise it sits still and costs nothing
    Timer {
        interval: 50; repeat: true
        running: win.visible && (hover.hovered || edit.activeFocus || win.gooShown !== win.goo)
        onTriggered: { win.t += 0.05; dots.requestPaint() }
    }

    // ---- the paper, drawn as Amiga AGA pixel art like the cabinet (dithered, chunky pixels) ----
    readonly property int sh: 6       // drop shadow offset (the paper is this much smaller than the window)
    readonly property int fold: 18    // the folded-over bottom-right corner, which is also the resize grip
    readonly property color black: "#141418"
    AgaPalette { id: aga; colors: win.app.aga }
    Item {
        id: art
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: false
        layer.effect: Dither { pal: aga.tex; count: aga.count }
        readonly property real w: card.width
        readonly property real h: card.height

        Shape {
            anchors.fill: parent
            // dithered drop shadow
            ShapePath {
                strokeWidth: -1; fillColor: Qt.rgba(0, 0, 0, 0.45)
                startX: win.sh; startY: win.sh
                PathLine { x: art.w + win.sh; y: win.sh }
                PathLine { x: art.w + win.sh; y: art.h + win.sh - win.fold }
                PathLine { x: art.w + win.sh - win.fold; y: art.h + win.sh }
                PathLine { x: win.sh; y: art.h + win.sh }
                PathLine { x: win.sh; y: win.sh }
            }
            // the sheet, with its corner folded away
            ShapePath {
                strokeColor: win.black; strokeWidth: 2; joinStyle: ShapePath.MiterJoin
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: 0; y2: art.h
                    GradientStop { position: 0; color: "#f4f3ec" }
                    GradientStop { position: 1; color: "#d9d7cb" }
                }
                startX: 1; startY: 1
                PathLine { x: art.w - 1; y: 1 }
                PathLine { x: art.w - 1; y: art.h - win.fold }
                PathLine { x: art.w - win.fold; y: art.h - 1 }
                PathLine { x: 1; y: art.h - 1 }
                PathLine { x: 1; y: 1 }
            }
        }

        // goo: a wave of the note's second colour that rises up the paper as you write
        Canvas {
            id: dots
            x: 2; y: win.headerH + 2
            width: art.w - 4; height: art.h - win.headerH - 3
            renderStrategy: Canvas.Cooperative
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()
            Connections { target: win; function onCiChanged() { dots.requestPaint() } function onGooShownChanged() { dots.requestPaint() } }
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                if (win.gooShown <= 0.005) return
                const top = height * (1 - win.gooShown)
                const wave = x => top + Math.sin(x * 0.045 + win.t * 2.2) * 4 + Math.sin(x * 0.11 - win.t * 1.3) * 2
                ctx.beginPath(); ctx.moveTo(0, height)
                for (let x = 0; x <= width; x += 4) ctx.lineTo(x, wave(x))
                ctx.lineTo(width, height); ctx.closePath()
                ctx.globalAlpha = 0.4; ctx.fillStyle = win.pal.b; ctx.fill()
                ctx.beginPath(); ctx.moveTo(0, wave(0))
                for (let x = 4; x <= width; x += 4) ctx.lineTo(x, wave(x))
                ctx.globalAlpha = 0.9; ctx.strokeStyle = win.pal.b; ctx.lineWidth = 3; ctx.stroke()
                // keep it off the folded corner
                ctx.globalCompositeOperation = "destination-out"; ctx.globalAlpha = 1
                ctx.beginPath(); ctx.moveTo(width - win.fold + 3, height + 1); ctx.lineTo(width + 1, height + 1); ctx.lineTo(width + 1, height - win.fold + 3); ctx.closePath(); ctx.fill()
            }
        }

        // header band in the note's colour, bevelled
        Rectangle {
            x: 2; y: 2; width: art.w - 4; height: win.headerH - 2
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(win.pal.a, 1.35) }
                GradientStop { position: 1; color: win.pal.a }
            }
        }
        Rectangle { x: 2; y: 2; width: art.w - 4; height: 2; color: "#f4f5f6" }
        Rectangle { x: 2; y: win.headerH; width: art.w - 4; height: 2; color: win.black }
        // category label card, pressed into the header
        Rectangle {
            x: catChip.x; y: catChip.y; width: catChip.width; height: catChip.height
            color: catArea.containsMouse || win.picking ? "#ffffff" : "#efeee6"
        }
        Rectangle { x: catChip.x; y: catChip.y; width: catChip.width; height: 2; color: win.black }
        Rectangle { x: catChip.x; y: catChip.y; width: 2; height: catChip.height; color: win.black }
        Rectangle { x: catChip.x; y: catChip.y + catChip.height - 2; width: catChip.width; height: 2; color: "#f4f5f6" }
        Rectangle { x: catChip.x + catChip.width - 2; y: catChip.y; width: 2; height: catChip.height; color: "#f4f5f6" }

        // the folded corner: the back of the sheet, turned over
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeColor: win.black; strokeWidth: 2; joinStyle: ShapePath.MiterJoin
                fillGradient: LinearGradient {
                    x1: art.w - win.fold; y1: art.h - win.fold; x2: art.w; y2: art.h
                    GradientStop { position: 0; color: gripArea.containsMouse || gripArea.pressed ? Qt.lighter(win.pal.a, 1.3) : "#c5c8cc" }
                    GradientStop { position: 1; color: gripArea.containsMouse || gripArea.pressed ? win.pal.a : "#f4f5f6" }
                }
                startX: art.w - 1; startY: art.h - win.fold
                PathLine { x: art.w - win.fold; y: art.h - 1 }
                PathLine { x: art.w - win.fold; y: art.h - win.fold }
                PathLine { x: art.w - 1; y: art.h - win.fold }
            }
        }

        // typing in it, or just found: a frame in the note's colour
        Rectangle {
            x: 0; y: 0; width: art.w; height: art.h
            visible: edit.activeFocus || win.glow > 0
            color: "transparent"
            border.color: win.pal.a; border.width: 2 + Math.round(win.glow * 2) * 2
        }
    }

    Item {
        id: card
        anchors { fill: parent; rightMargin: win.sh; bottomMargin: win.sh }

        HoverHandler { id: hover }

        // ---- header: drag strip + buttons --------------------------------
        Item {
            id: header
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: win.headerH

            MouseArea {
                id: dragArea
                anchors.fill: parent
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real sx: 0
                property real sy: 0
                property real lx: 0
                property real ly: 0
                property bool dirty: false
                onPressed: m => { sx = m.x; sy = m.y; lx = m.x; ly = m.y; edit.focus = false; win.app.dragNote = win.nid; track() }
                onPositionChanged: m => { lx = m.x; ly = m.y; dirty = true; track() }
                // tell the file cabinet where the pointer is (screen coords), so its drawers can open
                // under it. Read before the move is applied, while lx/ly are still relative to win.px/py
                function track() { win.app.dragX = win.px + lx; win.app.dragY = win.py + ly }
                onReleased: {
                    win.app.update(win.nid, { x: win.px, y: win.py })
                    const sx = win.app.dragX, sy = win.app.dragY
                    win.app.dragNote = ""
                    win.app.noteDropped(win.nid, sx, sy)
                }
                onCanceled: win.app.dragNote = ""
                // apply at most once a frame, so the compositor has caught up before the next step
                Timer {
                    interval: 16; repeat: true; running: dragArea.pressed
                    onTriggered: {
                        if (!dragArea.dirty) return
                        dragArea.dirty = false
                        win.px = Math.max(0, win.px + Math.round(dragArea.lx - dragArea.sx))
                        win.py = Math.max(0, win.py + Math.round(dragArea.ly - dragArea.sy))
                    }
                }
            }

            // category label: click to file the note somewhere
            Rectangle {
                id: catChip
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                width: Math.min(catLabel.implicitWidth + 18, buttons.x - 16)
                height: 20
                color: "transparent"   // drawn in the art layer
                PixelText {
                    id: catLabel
                    anchors { left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    text: (win.cat || "unsorted").toUpperCase()
                    elide: Text.ElideRight
                    font.pixelSize: 11
                    color: win.cat ? win.black : "#757980"
                }
                MouseArea {
                    id: catArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.picking = !win.picking
                }
            }

            Row {
                id: buttons
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                spacing: 2
                opacity: hover.hovered || edit.activeFocus || win.armed ? 1 : 0.55
                Behavior on opacity { NumberAnimation { duration: 180 } }

                NoteButton { glyph: ""; tip: win.pal.a; app: win.app; ink: win.black; pixel: true
                    onClicked: { win.ci = (win.ci + 1) % win.app.palette.length; win.app.update(win.nid, { color: win.ci }) } }
                NoteButton { glyph: ""; app: win.app; ink: win.black; pixel: true; lit: win.pinned; tip: win.pal.b
                    rotation: win.pinned ? 0 : 45
                    onClicked: { win.pinned = !win.pinned; win.app.update(win.nid, { pinned: win.pinned }) } }
                NoteButton { glyph: ""; app: win.app; ink: win.black; pixel: true; tip: win.pal.b
                    onClicked: win.app.stash(win.nid, true) }
                NoteButton { glyph: ""; app: win.app; ink: win.black; pixel: true; onClicked: win.app.drawerOpen = true }
                NoteButton { glyph: ""; app: win.app; ink: win.black; pixel: true; onClicked: win.app.newNote("", win.cat) }
                NoteButton { glyph: win.armed ? "" : ""; app: win.app; ink: win.black; pixel: true
                    lit: win.armed; tip: win.app.danger
                    onClicked: { if (win.armed) win.app.remove(win.nid); else { win.armed = true; disarm.restart() } } }
            }
            Timer { id: disarm; interval: 2500; onTriggered: win.armed = false }
        }

        // ---- body ----------------------------------------------------------
        Flickable {
            id: flick
            anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: footer.top
                      leftMargin: 16; rightMargin: 14; topMargin: 6 }
            contentWidth: width
            contentHeight: edit.contentHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            function follow(r) {
                if (r.y < contentY) contentY = r.y
                else if (r.y + r.height > contentY + height) contentY = r.y + r.height - height
            }

            TextEdit {
                id: edit
                width: flick.width
                wrapMode: TextEdit.Wrap
                color: win.black
                selectionColor: win.pal.a
                selectedTextColor: win.black
                font.family: "monospace"
                font.bold: true
                font.pixelSize: 13
                font.hintingPreference: Font.PreferFullHinting
                renderType: Text.NativeRendering
                cursorDelegate: Rectangle { width: 8; color: win.pal.a; border.color: win.black; border.width: 1; visible: edit.cursorVisible }
                selectByMouse: true
                persistentSelection: false
                onCursorRectangleChanged: flick.follow(cursorRectangle)
                onTextChanged: if (activeFocus) win.app.update(win.nid, { text: text })
                onActiveFocusChanged: {
                    if (activeFocus) win.app.typing = win.nid
                    else if (win.app.typing === win.nid) win.app.typing = ""
                }
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Escape) { edit.focus = false; e.accepted = true }
                    else if (e.key === Qt.Key_N && (e.modifiers & Qt.ControlModifier)) { win.app.newNote("", win.cat); e.accepted = true }
                }
            }
        }
        // click anywhere under the text to start typing at the end
        MouseArea {
            anchors { top: flick.top; topMargin: Math.min(flick.height, edit.contentHeight); left: flick.left; right: flick.right; bottom: flick.bottom }
            cursorShape: Qt.IBeamCursor
            onClicked: { edit.forceActiveFocus(); edit.cursorPosition = edit.length }
        }
        Text {
            anchors { top: flick.top; left: flick.left }
            visible: edit.length === 0 && !edit.activeFocus
            text: "write something..."
            color: "#8f949a"
            font.family: "monospace"
            font.bold: true
            font.pixelSize: 13
            renderType: Text.NativeRendering
        }

        // ---- footer: counters + resize grip --------------------------------
        Item {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 26
            PixelText {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: edit.length + " CH / " + (edit.text.length ? edit.text.split("\n").length : 0) + " LN"
                font.pixelSize: 9
                color: "#42454b"
                opacity: hover.hovered || edit.activeFocus ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
            PixelText {
                anchors { right: parent.right; rightMargin: win.fold + 8; verticalCenter: parent.verticalCenter }
                text: "GOO " + Math.round(win.goo * 100) + "%"
                font.pixelSize: 9
                color: "#42454b"
                opacity: hover.hovered || edit.activeFocus ? 0.9 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
        }

        // the folded corner is the resize grip; the window's top-left never moves while resizing, so window coords are exact
        Item {
            id: grip
            width: win.fold + 2; height: win.fold + 2
            anchors { right: parent.right; bottom: parent.bottom }
            MouseArea {
                id: gripArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.SizeFDiagCursor
                onPositionChanged: m => {
                    if (!pressed) return
                    const p = mapToItem(card, m.x, m.y)
                    win.pw = Math.max(260, Math.round(p.x + 6 + win.sh))
                    win.ph = Math.max(150, Math.round(p.y + 6 + win.sh))
                }
                onReleased: win.app.update(win.nid, { w: win.pw, h: win.ph })
            }
        }
    }

    // category menu over the note; click outside it to close
    MouseArea {
        anchors.fill: parent
        visible: win.picking
        onClicked: win.picking = false
        CategoryMenu {
            x: 10; y: win.headerH - 4
            app: win.app
            current: win.cat
            maxHeight: win.ph - win.headerH - 8
            onPicked: name => { win.app.setCategory(win.nid, name); win.picking = false }
            onDismissed: win.picking = false
        }
    }

    readonly property alias body: edit
}
