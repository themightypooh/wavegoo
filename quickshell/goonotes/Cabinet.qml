// The file cabinet: a steel cabinet on the desktop, seen head-on from above, drawn like Amiga AGA
// pixel art: a small fixed palette (a steel ramp, oranges, paper, the note colours), chunky pixels,
// ordered dithering for shading and a dithered drop shadow (Dither.qml, shaders/aga.frag). One drawer per category (the first three).
// While a note is being dragged every drawer cracks open a little, and the one under the pointer
// slides right out; let go over it to file the note there and put it away.
// Hover a drawer and it slides out toward you with the notes filed in it standing up like file
// folders, titles on the tabs; click a tab to take that note out. Click a drawer front to browse it
// in the notes drawer; right-click it to rename the drawer. Drag the top of the cabinet to move it.
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: cab
    required property var app

    // ---- AGA-style palette: everything drawn below is dithered into these (max 32) -------------
    readonly property color pWhite: "#f4f5f6"
    readonly property color pBlack: "#141418"
    readonly property color pOrange: "#ff8800"
    readonly property var aga: app.aga
    // the palette as a texture strip, one texel per colour, for the dither shader
    Row {
        id: palStrip
        Repeater { model: cab.aga; Rectangle { required property string modelData; width: 1; height: 1; color: modelData } }
    }
    ShaderEffectSource {
        id: palTex
        sourceItem: palStrip
        hideSource: true
        smooth: false
        textureSize: Qt.size(cab.aga.length, 1)
        width: 1; height: 1; visible: false
    }
    readonly property real chunk: 2              // size of one chunky pixel
    readonly property string pixelFont: "monospace"

    // ---- shape -----------------------------------------------------------------------
    readonly property real fw: 180               // front face
    readonly property real fh: 300
    readonly property real topH: 48              // the top, seen from above
    readonly property real topIn: 22             // ...narrowing as it goes back
    readonly property real pad: 10               // inset of the drawers inside the front
    readonly property real gap: 12
    readonly property int count: 3
    readonly property real dh: (fh - pad * 2 - gap * (count - 1)) / count
    // drawers slide straight toward you: down the screen, a little wider as they come closer
    readonly property real dragOut: 34           // under a dragged note
    readonly property real hoverOut: 66          // showing its files
    readonly property real widen: 7              // extra width per side when fully out
    // file folders standing in an open drawer
    readonly property real riseH: 18
    readonly property real tabH: 14
    readonly property int maxFiles: 7
    readonly property real step: 7               // each folder further back stands this much taller
    readonly property real filesUp: riseH + tabH + step * (maxFiles - 1) + 4
    readonly property real shadow: 8             // drop shadow offset
    // where the front face's top-left sits inside the window (room for the top drawer's folders,
    // and for the bottom drawer sliding out)
    readonly property real ox: 10 + widen
    readonly property real oy: Math.max(topH, filesUp - pad) + 6

    // ---- place on the desktop: same coordinates as the notes (top-left of the screen) ------
    readonly property int maxX: (screen ? screen.width : 1920) - implicitWidth
    readonly property int maxY: (screen ? screen.height : 1080) - implicitHeight
    function clampX(x) { return Math.max(0, Math.min(maxX, x)) }
    function clampY(y) { return Math.max(0, Math.min(maxY, y)) }
    property int px: clampX((app.cabinet && app.cabinet.x !== undefined) ? app.cabinet.x : maxX - 60)
    property int py: clampY((app.cabinet && app.cabinet.y !== undefined) ? app.cabinet.y : 140)
    screen: app.screenFor("")
    visible: app.shown
    color: "transparent"
    anchors { top: true; left: true }
    margins { top: cab.py; left: cab.px }
    implicitWidth: ox + fw + widen + shadow + 10
    implicitHeight: oy + fh + hoverOut + shadow + 12
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "goonotes-cabinet"
    WlrLayershell.layer: app.cabinetPeek ? WlrLayer.Top : WlrLayer.Bottom
    // takes the keyboard when clicked, so a right-click can go straight into renaming a drawer
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // only the cabinet itself (and an open drawer's folders) catch the mouse; the empty corners
    // of the window are click-through to the desktop
    mask: Region {
        item: bodyHit
        Region { item: filesHit }
    }
    Item { id: bodyHit; x: cab.ox - cab.widen; y: cab.oy - cab.topH; width: cab.fw + cab.widen * 2; height: cab.topH + cab.fh + cab.openOut }
    Item {
        id: filesHit
        x: cab.ox; width: cab.fw
        y: cab.hoverIdx >= 0 ? cab.oy + cab.pad + cab.hoverIdx * (cab.dh + cab.gap) - cab.filesUp : 0
        height: cab.hoverIdx >= 0 ? cab.filesUp : 0
    }
    // how far the bottom drawer is out, so the mouse area follows it
    property real openOut: 0

    // brought up from the bar: sinks back to the desktop after 15 s without the pointer on it
    Item { anchors.fill: parent; HoverHandler { id: cabHover } }
    Timer {
        interval: 15000
        running: cab.app.cabinetPeek && !cabHover.hovered && !cab.app.drawerOpen && !cab.dragging && cab.renameIdx < 0
        onTriggered: cab.app.cabinetPeek = false
    }

    // which drawer the dragged note is over (-1 = none), from the pointer in screen coords
    function drawerAt(sx, sy) {
        const x = sx - px - ox, y = sy - py - oy
        if (x < -30 || x > fw + 30 || y < -topH - 10 || y > fh + 30) return -1
        for (let i = 0; i < count; i++) {
            const t = pad + i * (dh + gap)
            if (y >= t - gap / 2 && y <= t + dh + gap / 2) return i
        }
        return y < pad ? 0 : count - 1
    }
    readonly property bool dragging: app.dragNote !== ""
    readonly property bool near: dragging && Math.hypot(app.dragX - (px + ox + fw / 2), app.dragY - (py + oy + fh / 2)) < 420
    readonly property int target: dragging ? drawerAt(app.dragX, app.dragY) : -1
    function catFor(i) { return i < app.categories.length ? app.categories[i] : "" }

    // let go of a note over a drawer: file it and put it away
    Connections {
        target: cab.app
        function onNoteDropped(id, sx, sy) {
            const i = cab.drawerAt(sx, sy)
            if (i < 0 || !cab.catFor(i)) return
            cab.app.setCategory(id, cab.catFor(i))
            cab.app.stash(id, true)
            cab.thunk = i; thunkAnim.restart()
        }
    }
    property int thunk: -1          // the drawer that just took a note: it shuts with a little bump
    property real bump: 0
    SequentialAnimation {
        id: thunkAnim
        NumberAnimation { target: cab; property: "bump"; from: 0; to: 1; duration: 90 }
        NumberAnimation { target: cab; property: "bump"; to: 0; duration: 380; easing.type: Easing.OutBack }
    }

    // ---- renaming: right-click a drawer front ---------------------------------------------
    property int renameIdx: -1
    function finishRename(text) {
        const i = renameIdx
        renameIdx = -1
        if (i < 0) return
        const old = catFor(i)
        if (old) app.renameCategory(old, text)
        else app.addCategory(text)   // an empty drawer: becomes a new category
    }

    // the dither pass (Dither.qml) and crisp text (PixelText.qml) live in their own files

    // ---- the carcass: shadow, top strip, front ------------------------------------------
    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: false
        layer.effect: Dither { px: cab.chunk; pal: palTex; count: cab.aga.length }

        // dithered drop shadow
        Rectangle {
            x: cab.ox + cab.shadow; y: cab.oy - cab.topH + cab.shadow
            width: cab.fw; height: cab.topH + cab.fh + 5
            color: Qt.rgba(0, 0, 0, 0.5)
        }
        Shape {
            anchors.fill: parent
            // top, receding away from you: lit from above, so white dithered into blue
            ShapePath {
                strokeColor: cab.pBlack; strokeWidth: 2; joinStyle: ShapePath.MiterJoin
                fillGradient: LinearGradient {
                    x1: 0; y1: cab.oy - cab.topH; x2: 0; y2: cab.oy
                    GradientStop { position: 0; color: "#9ea2a8" }
                    GradientStop { position: 0.8; color: "#d3d6d9" }
                    GradientStop { position: 1; color: "#eceef0" }
                }
                startX: cab.ox; startY: cab.oy
                PathLine { x: cab.ox + cab.topIn; y: cab.oy - cab.topH }
                PathLine { x: cab.ox + cab.fw - cab.topIn; y: cab.oy - cab.topH }
                PathLine { x: cab.ox + cab.fw; y: cab.oy }
                PathLine { x: cab.ox; y: cab.oy }
            }
        }
        // front: blue, darkening toward the floor
        Rectangle {
            x: cab.ox; y: cab.oy; width: cab.fw; height: cab.fh
            border.color: cab.pBlack; border.width: 2
            gradient: Gradient {
                GradientStop { position: 0; color: "#b6babe" }
                GradientStop { position: 0.7; color: "#8c9096" }
                GradientStop { position: 1; color: "#5d6166" }
            }
        }
        // bevel: white on the top-left edges, black on the bottom-right
        Rectangle { x: cab.ox + 2; y: cab.oy + 2; width: cab.fw - 4; height: 2; color: cab.pWhite }
        Rectangle { x: cab.ox + 2; y: cab.oy + 2; width: 2; height: cab.fh - 4; color: cab.pWhite }
        Rectangle { x: cab.ox + 2; y: cab.oy + cab.fh - 4; width: cab.fw - 4; height: 2; color: cab.pBlack }
        Rectangle { x: cab.ox + cab.fw - 4; y: cab.oy + 2; width: 2; height: cab.fh - 4; color: cab.pBlack }
        // sheen on the steel: soft highlights that dither out to sparse white
        Rectangle { x: cab.ox + 22; y: cab.oy + 4; width: 14; height: cab.fh - 8; color: Qt.rgba(1, 1, 1, 0.22) }
        Rectangle { x: cab.ox + 40; y: cab.oy + 4; width: 5; height: cab.fh - 8; color: Qt.rgba(1, 1, 1, 0.15) }
        // the bright front lip under the top, and a darker band at the right edge
        Rectangle { x: cab.ox; y: cab.oy - 2; width: cab.fw; height: 4; color: cab.pWhite }
        Rectangle { x: cab.ox + cab.fw - 30; y: cab.oy + 4; width: 10; height: cab.fh - 8; color: Qt.rgba(0, 0, 0, 0.12) }
        // feet
        Rectangle { x: cab.ox + 8; y: cab.oy + cab.fh; width: 18; height: 6; color: cab.pBlack }
        Rectangle { x: cab.ox + cab.fw - 26; y: cab.oy + cab.fh; width: 18; height: 6; color: cab.pBlack }
    }

    // ---- the drawers ---------------------------------------------------------------------
    // Only one drawer shows its files at a time: the one you hovered first keeps them while the
    // pointer is anywhere over it or its folders.
    property int hoverIdx: -1
    property bool zoneHeld: false
    Timer {
        interval: 260
        running: cab.hoverIdx >= 0 && !cab.zoneHeld && cab.renameIdx < 0
        onTriggered: cab.hoverIdx = -1
    }

    Repeater {
        model: cab.count
        delegate: Item {
            id: dw
            required property int index
            anchors.fill: parent
            readonly property string cat: { cab.app.rev; return cab.catFor(index) }
            readonly property int notes: { cab.app.rev; return cab.app.ids.filter(i => (cab.app.store[i] || {}).category === dw.cat && dw.cat).length }
            // notes filed (put away) in this drawer, newest first
            readonly property var files: {
                cab.app.rev
                if (!dw.cat) return []
                return cab.app.ids.map(i => cab.app.store[i])
                    .filter(n => n && n.stashed && n.category === dw.cat)
                    .sort((a, b) => (b.updated || b.created || 0) - (a.updated || a.created || 0))
            }
            readonly property int n: Math.min(files.length, cab.maxFiles)
            readonly property bool hot: cab.target === index && !!cat
            readonly property bool renaming: cab.renameIdx === index
            readonly property bool front: hoverArea.containsMouse && !cab.dragging
            readonly property bool showing: cab.hoverIdx === index && !cab.dragging && files.length > 0 && !renaming
            // how far out it is, in px toward you: a crack while a note is dragged nearby, further
            // under the note, all the way while it shows its files
            readonly property real want: hot ? cab.dragOut : cab.near && cat ? 8 : showing ? cab.hoverOut : cab.hoverIdx === index && !cab.dragging ? 6 : 0
            property real slide: want
            Behavior on slide { SpringAnimation { spring: 4; damping: 0.4; epsilon: 0.2 } }
            readonly property real out: Math.round(Math.max(0, slide - (cab.thunk === index ? cab.bump * 6 : 0)) / cab.chunk) * cab.chunk
            onOutChanged: if (index === cab.count - 1) cab.openOut = out
            // the slot in the cabinet front
            readonly property real sx: cab.ox + cab.pad
            readonly property real sy: cab.oy + cab.pad + index * (cab.dh + cab.gap)
            readonly property real sw: cab.fw - cab.pad * 2
            // the drawer front, slid toward you: lower, and a touch wider since it's closer
            readonly property real e: Math.round(cab.widen * out / cab.hoverOut)
            readonly property real fx: sx - e
            readonly property real fy: sy + out
            readonly property real fwd: sw + e * 2
            z: out > 0.5 || renaming ? 2 + out / 100 : 1

            // where folder k stands (0 = right behind the front, newest)
            function folder(k) {
                const u = n === 1 ? 0.4 : 0.08 + 0.84 * k / (n - 1)
                const bx = Math.round(fx + (sx - fx) * u + 6), by = Math.round(fy + (sy - fy) * u)
                const cw = Math.round(fwd + (sw - fwd) * u - 12)
                const rise = cab.riseH + k * cab.step
                const tw = Math.round(cw * 0.72)
                return { bx: bx, by: by, cw: cw, rise: rise, tw: tw, tx: bx + Math.round((k % 3) * (cw - tw) / 2) }
            }
            property real lift: showing ? 1 : 0
            Behavior on lift { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
            property int hoverTab: -1

            // hovering the front claims the drawer (unless another one is still being looked at)
            function claim() { if (front && (cab.hoverIdx < 0 || (cab.hoverIdx !== index && !cab.zoneHeld))) cab.hoverIdx = index }
            onFrontChanged: claim()
            Connections { target: cab; function onHoverIdxChanged() { if (cab.hoverIdx < 0) dw.claim() } }
            Binding { when: cab.hoverIdx === dw.index; target: cab; property: "zoneHeld"; value: dw.front || zone.hovered }

            // the area that keeps the files showing: the pulled-out drawer and the folders above it
            Item {
                x: dw.fx - 2; y: dw.sy - cab.filesUp
                width: dw.fwd + 4; height: dw.fy + cab.dh - y
                enabled: cab.hoverIdx === dw.index
                HoverHandler { id: zone }
            }

            // ---- art, dithered ----
            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.smooth: false
                layer.effect: Dither { px: cab.chunk; pal: palTex; count: cab.aga.length }

                // the black slot it slides out of
                Rectangle { x: dw.sx; y: dw.sy; width: dw.sw; height: cab.dh; color: cab.pBlack }
                // looking down into the drawer as it comes out: dark, black dithered into blue
                Shape {
                    anchors.fill: parent
                    visible: dw.out > 0
                    ShapePath {
                        strokeColor: cab.pBlack; strokeWidth: 2; joinStyle: ShapePath.MiterJoin
                        fillGradient: LinearGradient {
                            x1: 0; y1: dw.sy; x2: 0; y2: dw.fy
                            GradientStop { position: 0; color: "#141418" }
                            GradientStop { position: 1; color: "#44484d" }
                        }
                        startX: dw.sx; startY: dw.sy
                        PathLine { x: dw.sx + dw.sw; y: dw.sy }
                        PathLine { x: dw.fx + dw.fwd; y: dw.fy }
                        PathLine { x: dw.fx; y: dw.fy }
                        PathLine { x: dw.sx; y: dw.sy }
                    }
                }
                // the folders, back ones first
                Repeater {
                    model: dw.n
                    Item {
                        id: fold
                        required property int index
                        readonly property var g: dw.folder(index)
                        readonly property real h: Math.round(g.rise * dw.lift)
                        anchors.fill: parent
                        z: dw.n - index
                        visible: dw.lift > 0.02
                        // body: white paper, greying toward the bottom
                        Rectangle {
                            x: fold.g.bx; y: fold.g.by - fold.h; width: fold.g.cw; height: fold.h
                            border.color: cab.pBlack; border.width: 2
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#ffffff" }
                                GradientStop { position: 1; color: "#c4c3bc" }
                            }
                        }
                        // tab: orange, white when hovered
                        Rectangle {
                            x: fold.g.tx; y: fold.g.by - fold.h - Math.round(cab.tabH * dw.lift) + 2
                            width: fold.g.tw; height: Math.round(cab.tabH * dw.lift)
                            readonly property var note: dw.files[fold.index] || ({})
                            color: dw.hoverTab === fold.index ? cab.pWhite : cab.app.palette[(note.color || 0) % cab.app.palette.length].a
                            border.color: cab.pBlack; border.width: 2
                        }
                    }
                }
                // the drawer front: bevelled blue panel
                Rectangle {
                    x: dw.fx; y: dw.fy; width: dw.fwd; height: cab.dh
                    border.color: dw.hot ? cab.pOrange : cab.pBlack; border.width: dw.hot ? 4 : 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: dw.front || dw.hot ? "#ccd0d4" : "#adb1b6" }
                        GradientStop { position: 1; color: "#6b6f74" }
                    }
                }
                Rectangle { x: dw.fx + 2; y: dw.fy + 2; width: dw.fwd - 4; height: 2; color: cab.pWhite }
                Rectangle { x: dw.fx + 2; y: dw.fy + 2; width: 2; height: cab.dh - 4; color: cab.pWhite }
                Rectangle { x: dw.fx + 2; y: dw.fy + cab.dh - 4; width: dw.fwd - 4; height: 2; color: cab.pBlack }
                Rectangle { x: dw.fx + dw.fwd - 4; y: dw.fy + 2; width: 2; height: cab.dh - 4; color: cab.pBlack }
                // label holder: inset (black top-left, white bottom-right)
                Rectangle {
                    id: plate
                    width: Math.min(dw.fwd - 28, 120); height: 24
                    x: Math.round(dw.fx + (dw.fwd - width) / 2); y: dw.fy + 12
                    color: dw.renaming ? cab.pWhite : "#e4e3dc"
                }
                Rectangle { x: plate.x; y: plate.y; width: plate.width; height: 2; color: cab.pBlack }
                Rectangle { x: plate.x; y: plate.y; width: 2; height: plate.height; color: cab.pBlack }
                Rectangle { x: plate.x; y: plate.y + plate.height - 2; width: plate.width; height: 2; color: cab.pWhite }
                Rectangle { x: plate.x + plate.width - 2; y: plate.y; width: 2; height: plate.height; color: cab.pWhite }
                // pull handle: orange bar
                Rectangle {
                    x: Math.round(dw.fx + dw.fwd / 2 - 20); y: dw.fy + cab.dh - 18; width: 40; height: 8
                    border.color: cab.pBlack; border.width: 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#f4f5f6" }
                        GradientStop { position: 1; color: "#757980" }
                    }
                }
            }

            // ---- text, crisp ----
            Repeater {
                model: dw.n
                Item {
                    id: tabText
                    required property int index
                    readonly property var g: dw.folder(index)
                    readonly property var note: dw.files[index] || ({})
                    readonly property bool more: index === dw.n - 1 && dw.files.length > cab.maxFiles
                    x: g.tx; y: g.by - g.rise - cab.tabH + 2
                    width: g.tw; height: cab.tabH
                    z: dw.n - index + 0.5
                    visible: dw.lift > 0.9
                    PixelText {
                        anchors { fill: parent; leftMargin: 5; rightMargin: 4 }
                        verticalAlignment: Text.AlignVCenter
                        text: tabText.more ? "+" + (dw.files.length - cab.maxFiles + 1) + " MORE"
                            : ((tabText.note.text || "").split("\n").find(l => l.trim()) || "untitled").trim()
                        elide: Text.ElideRight
                        font.pixelSize: 9
                        color: cab.pBlack
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: dw.hoverTab = containsMouse ? tabText.index : (dw.hoverTab === tabText.index ? -1 : dw.hoverTab)
                        // take it out of the drawer and onto the desktop ("+N more" opens the browser)
                        onClicked: {
                            if (tabText.more) cab.app.browse(dw.cat)
                            else cab.app.reveal(tabText.note.id)
                            dw.hoverTab = -1
                            cab.hoverIdx = -1
                        }
                    }
                }
            }
            PixelText {
                visible: !dw.renaming
                x: dw.fx; width: dw.fwd; y: dw.fy + 12; height: 24
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                leftPadding: 18; rightPadding: 18
                text: (dw.cat || "empty").toUpperCase()
                elide: Text.ElideRight
                font.pixelSize: 12
                color: dw.cat ? cab.pBlack : "#7a7e84"
            }
            PixelText {
                x: dw.fx; width: dw.fwd; y: dw.fy + 42
                horizontalAlignment: Text.AlignHCenter
                text: dw.renaming ? "ENTER = OK  ESC = CANCEL"
                    : dw.cat ? (dw.files.length + " FILED" + (dw.notes > dw.files.length ? " / " + (dw.notes - dw.files.length) + " OUT" : ""))
                    : "RIGHT-CLICK TO NAME"
                font.pixelSize: 9
                color: cab.pBlack
            }
            MouseArea {
                id: hoverArea
                x: dw.fx; y: dw.fy; width: dw.fwd; height: cab.dh
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: dw.cat ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: m => {
                    if (m.button === Qt.RightButton) { cab.hoverIdx = -1; cab.renameIdx = dw.index }
                    else if (dw.cat && !dw.renaming) cab.app.browse(dw.cat)
                }
            }
            // the name field, over the label holder while renaming
            TextInput {
                id: nameField
                visible: dw.renaming
                x: Math.round(dw.fx + (dw.fwd - width) / 2); y: dw.fy + 12
                width: Math.min(dw.fwd - 28, 120) - 12; height: 24
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                clip: true
                maximumLength: 24
                font.family: cab.pixelFont; font.bold: true; font.pixelSize: 12
                font.capitalization: Font.AllUppercase
                renderType: Text.NativeRendering
                color: cab.pBlack
                selectionColor: cab.pOrange
                selectedTextColor: cab.pBlack
                cursorDelegate: Rectangle { width: 7; color: cab.pOrange; visible: nameField.cursorVisible }
                onVisibleChanged: if (visible) { text = dw.cat; selectAll(); forceActiveFocus() }
                onAccepted: cab.finishRename(text)
                Keys.onEscapePressed: cab.renameIdx = -1
                onActiveFocusChanged: if (!activeFocus && dw.renaming) cab.renameIdx = -1
            }
        }
    }

    // ---- drag the top to move the cabinet ----------------------------------------------
    // Same as dragging a note: the window moves under the pointer, so apply the move at most once a
    // frame (after the compositor has caught up), or each move feeds into the next and it flies off.
    MouseArea {
        id: moveArea
        x: cab.ox; y: cab.oy - cab.topH; width: cab.fw; height: cab.topH + 2
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real sx: 0
        property real sy: 0
        property real lx: 0
        property real ly: 0
        property bool dirty: false
        onPressed: m => { sx = m.x; sy = m.y; lx = m.x; ly = m.y }
        onPositionChanged: m => { lx = m.x; ly = m.y; dirty = true }
        onReleased: cab.app.setCabinet(cab.px, cab.py)
        Timer {
            interval: 16; repeat: true; running: moveArea.pressed
            onTriggered: {
                if (!moveArea.dirty) return
                moveArea.dirty = false
                cab.px = cab.clampX(cab.px + Math.round(moveArea.lx - moveArea.sx))
                cab.py = cab.clampY(cab.py + Math.round(moveArea.ly - moveArea.sy))
            }
        }
    }
}
