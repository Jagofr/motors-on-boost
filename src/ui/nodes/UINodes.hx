package ui.nodes;

import graphics.SceneGraph.TextureHandle;
import haxe.io.Bytes;
import math.Vec3;

class UIPoint {
    public var x:Float;
    public var y:Float;

    public inline function new(x:Float = 0.0, y:Float = 0.0) {
        this.x = x;
        this.y = y;
    }

    public inline function set(x:Float = 0.0, y:Float = 0.0):Void {
        this.x = x;
        this.y = y;
    }

    public inline function load(p:UIPoint):Void {
        this.x = p.x;
        this.y = p.y;
    }

    public inline function clone():UIPoint {
        return new UIPoint(x, y);
    }
}

enum UIEventKind {
    EPush;
    ERelease;
    EReleaseOutside;
    EMove;
    EOver;
    EOut;
    ECheck;
}

class UIEvent {
    public var kind:UIEventKind;
    public var relX:Float;
    public var relY:Float;
    public var wheelDelta:Float = 0.0;
    public var touchId:Int = 0;
    public var button:Int = 0;
    public var propagate:Bool = false;
    public var cancel:Bool = false;

    public function new(kind:UIEventKind, relX:Float = 0.0, relY:Float = 0.0) {
        this.kind = kind;
        this.relX = relX;
        this.relY = relY;
    }
}

enum UITextAlign {
    Left;
    Center;
    Right;
}

enum UIScaleMode {
    Resize;
    LetterBox(width:Int, height:Int, ?integerScale:Bool);
    Fixed(width:Int, height:Int, ?zoom:Float);
}

enum UICursor {
    Default;
    Button;
    TextInput;
    Hide;
}

class UIFont {
    public var name:String;
    public var size:Int;
    public var lineHeight:Float;
    public var baseLine:Float;

    public function new(name:String = "default", size:Int = 16) {
        this.name = name;
        this.size = size;
        this.lineHeight = size * 1.25;
        this.baseLine = size * 0.95;
    }

    public function calcTextWidth(text:String):Float {
        if (text == null || text.length == 0) return 0.0;
        var maxLine = 0;
        for (line in text.split("\n")) {
            if (line.length > maxLine) maxLine = line.length;
        }
        return maxLine * size * 0.54;
    }

    public function resizeTo(newSize:Int):Void {
        size = newSize > 4 ? newSize : 4;
        lineHeight = size * 1.25;
        baseLine = size * 0.95;
    }

    public function clone():UIFont {
        var f = new UIFont(name, size);
        f.lineHeight = lineHeight;
        f.baseLine = baseLine;
        return f;
    }

    public function dispose():Void {}
}

class UIPixels {
    public var width:Int;
    public var height:Int;
    public var bytes:Bytes;

    public function new(width:Int, height:Int, ?bytes:Bytes) {
        this.width = width;
        this.height = height;
        this.bytes = bytes != null ? bytes : Bytes.alloc(width * height * 4);
    }

    public static function alloc(width:Int, height:Int):UIPixels {
        return new UIPixels(width, height);
    }
}

class UIBitmapData {
    public var width:Int;
    public var height:Int;
    public var bytes:Bytes;

    public function new(width:Int, height:Int) {
        this.width = width;
        this.height = height;
        this.bytes = Bytes.alloc(width * height * 4);
    }

    public function setPixels(p:UIPixels):Void {
        if (p == null) return;
        this.width = p.width;
        this.height = p.height;
        this.bytes = p.bytes;
    }
}

class UITile {
    public var width:Float;
    public var height:Float;
    public var dx:Float = 0.0;
    public var dy:Float = 0.0;
    public var color:Int = 0xFFFFFFFF;
    public var url:String = "";
    public var texture:Null<TextureHandle> = null;

    public function new(w:Float = 1.0, h:Float = 1.0, dx:Float = 0.0, dy:Float = 0.0) {
        this.width = w;
        this.height = h;
        this.dx = dx;
        this.dy = dy;
    }

    public static function fromColor(color:Int, width:Int = 1, height:Int = 1, alpha:Float = 1.0):UITile {
        var t = new UITile(width, height);
        t.color = (color & 0xFFFFFF) | (Math.round(alpha * 255.0) << 24);
        t.texture = TextureHandle.fromColor(color, alpha);
        return t;
    }

    public static function fromTexture(tex:TextureHandle):UITile {
        var t = new UITile(tex != null ? tex.width : 1, tex != null ? tex.height : 1);
        t.texture = tex;
        t.color = tex != null ? tex.solidColor : 0xFFFFFFFF;
        return t;
    }

    public static function fromBitmapData(bmp:UIBitmapData, ?url:String):UITile {
        var tex = new TextureHandle(bmp.width, bmp.height, bmp.bytes, 0xFFFFFFFF);
        var t = fromTexture(tex);
        if (url != null) t.url = url;
        return t;
    }

    public function sub(x:Float, y:Float, w:Float, h:Float, dx:Float = 0.0, dy:Float = 0.0):UITile {
        var t = new UITile(w, h, dx, dy);
        t.color = color;
        t.texture = texture;
        t.url = url;
        return t;
    }

    public function center():UITile {
        dx = -width * 0.5;
        dy = -height * 0.5;
        return this;
    }

    public function setCenterRatio(rx:Float = 0.5, ry:Float = 0.5):UITile {
        dx = -width * rx;
        dy = -height * ry;
        return this;
    }

    public function clone():UITile {
        var copy = new UITile(width, height, dx, dy);
        copy.color = color;
        copy.url = url;
        copy.texture = texture;
        return copy;
    }

    public function scaleToSize(w:Float, h:Float):Void {
        width = w;
        height = h;
    }
}

class UIObject {
    public var name:String = "";
    public var x:Float = 0.0;
    public var y:Float = 0.0;
    public var scaleX:Float = 1.0;
    public var scaleY:Float = 1.0;
    public var rotation:Float = 0.0;
    public var alpha:Float = 1.0;
    public var visible:Bool = true;
    public var parent:Null<UIObject> = null;
    public var children:Array<UIObject>;

    public var numChildren(get, never):Int;
    inline function get_numChildren():Int return children.length;

    public function new(?parent:UIObject) {
        children = [];
        if (parent != null) parent.addChild(this);
    }

    public function addChild(child:UIObject):Void {
        if (child == null || child == this) return;
        if (child.parent != null && child.parent != this) {
            child.parent.removeChild(child);
        }
        if (child.parent != this) {
            child.parent = this;
            children.push(child);
        }
    }

    public function addChildAt(child:UIObject, index:Int):Void {
        if (child == null || child == this) return;
        if (child.parent != null) child.parent.removeChild(child);
        child.parent = this;
        var pos = index < 0 ? 0 : (index > children.length ? children.length : index);
        children.insert(pos, child);
    }

    public function removeChild(child:UIObject):Void {
        if (child == null) return;
        if (children.remove(child)) {
            if (child.parent == this) child.parent = null;
        }
    }

    public function remove():Void {
        if (parent != null) parent.removeChild(this);
    }

    public function removeChildren():Void {
        for (c in children) c.parent = null;
        children.resize(0);
    }

    public function setScale(s:Float):Void {
        scaleX = s;
        scaleY = s;
    }

    public function scale(s:Float):Void {
        scaleX *= s;
        scaleY *= s;
    }

    public function onRemove():Void {}

    public function setPosition(px:Float, py:Float):Void {
        x = px;
        y = py;
    }

    public function getScene():Null<UIScene2D> {
        var cur:Null<UIObject> = this;
        while (cur != null) {
            if (Std.isOfType(cur, UIScene2D)) return cast cur;
            cur = cur.parent;
        }
        return null;
    }

    public function localToGlobal(pt:UIPoint):UIPoint {
        var gx = pt.x;
        var gy = pt.y;
        var cur:Null<UIObject> = this;
        while (cur != null) {
            gx = gx * cur.scaleX + cur.x;
            gy = gy * cur.scaleY + cur.y;
            cur = cur.parent;
        }
        pt.x = gx;
        pt.y = gy;
        return pt;
    }

    public function globalToLocal(pt:UIPoint):UIPoint {
        var chain:Array<UIObject> = [];
        var cur:Null<UIObject> = this;
        while (cur != null) {
            chain.push(cur);
            cur = cur.parent;
        }
        var lx = pt.x;
        var ly = pt.y;
        var i = chain.length - 1;
        while (i >= 0) {
            var n = chain[i];
            lx = n.scaleX != 0 ? (lx - n.x) / n.scaleX : 0.0;
            ly = n.scaleY != 0 ? (ly - n.y) / n.scaleY : 0.0;
            i--;
        }
        pt.x = lx;
        pt.y = ly;
        return pt;
    }
}

typedef UIDropShadow = {
    var dx:Float;
    var dy:Float;
    var color:Int;
    var alpha:Float;
};

class UIText extends UIObject {
    public var font:UIFont;
    public var text:String = "";
    public var textColor:Int = 0xFFFFFFFF;
    public var textAlign:UITextAlign = UITextAlign.Left;
    public var maxWidth:Null<Float> = null;
    public var lineSpacing:Float = 0.0;
    public var letterSpacing:Float = 0.0;
    public var dropShadow:Null<UIDropShadow> = null;

    public var textWidth(get, never):Float;
    public var textHeight(get, never):Float;

    public function new(font:UIFont, ?parent:UIObject) {
        super(parent);
        this.font = font != null ? font : new UIFont("default", 16);
    }

    public function calcTextWidth(s:String):Float {
        return font.calcTextWidth(s) + (s != null ? s.length * letterSpacing : 0.0);
    }

    function get_textWidth():Float {
        var w = calcTextWidth(text);
        if (maxWidth != null && w > maxWidth) return maxWidth;
        return w;
    }

    function get_textHeight():Float {
        if (text == null || text.length == 0) return font.lineHeight;
        var lines = text.split("\n");
        var totalLines = 0;
        var limit = maxWidth != null && maxWidth > 0 ? maxWidth : 1e9;
        for (line in lines) {
            var w = calcTextWidth(line);
            if (w <= limit || line.length == 0) {
                totalLines += 1;
            } else {
                totalLines += Math.ceil(w / limit);
            }
        }
        if (totalLines < 1) totalLines = 1;
        return totalLines * (font.lineHeight + lineSpacing);
    }
}

class UIBitmap extends UIObject {
    public var tile:Null<UITile>;
    public var color:Vec3;
    public var colorAdd:Null<Vec3> = null;
    public var smooth:Bool = false;

    public var width(get, never):Float;
    public var height(get, never):Float;

    public function new(?tile:UITile, ?parent:UIObject) {
        super(parent);
        this.tile = tile;
        this.color = new Vec3(1.0, 1.0, 1.0, 1.0);
    }

    function get_width():Float return tile != null ? tile.width : 0.0;
    function get_height():Float return tile != null ? tile.height : 0.0;
}

class UIGraphics extends UIObject {
    public var fillColor:Int = 0;
    public var fillAlpha:Float = 0.0;
    public var strokeSize:Float = 0.0;
    public var strokeColor:Int = 0;
    public var strokeAlpha:Float = 0.0;
    public var drawCount:Int = 0;

    public function new(?parent:UIObject) {
        super(parent);
    }

    public function clear():Void {
        fillAlpha = 0.0;
        strokeAlpha = 0.0;
        drawCount = 0;
    }

    public function beginFill(color:Int = 0, alpha:Float = 1.0):Void {
        fillColor = color;
        fillAlpha = alpha;
    }

    public function endFill():Void {}

    public function lineStyle(size:Float = 0.0, color:Int = 0, alpha:Float = 1.0):Void {
        strokeSize = size;
        strokeColor = color;
        strokeAlpha = alpha;
    }

    public function drawRect(x:Float, y:Float, w:Float, h:Float):Void { drawCount++; }
    public function drawRoundedRect(x:Float, y:Float, w:Float, h:Float, radius:Float, nsegments:Int = 0):Void { drawCount++; }
    public function drawCircle(cx:Float, cy:Float, radius:Float, nsegments:Int = 0):Void { drawCount++; }
    public function drawPie(cx:Float, cy:Float, radius:Float, angleStart:Float, angleLength:Float, nsegments:Int = 0):Void { drawCount++; }
    public function moveTo(x:Float, y:Float):Void {}
    public function lineTo(x:Float, y:Float):Void { drawCount++; }
    public function curveTo(cx:Float, cy:Float, x:Float, y:Float):Void { drawCount++; }
    public function drawTo(tex:TextureHandle):Void {}
}

class UIInteractive extends UIObject {
    public var width:Float;
    public var height:Float;
    public var cursor:UICursor = UICursor.Button;
    public var propagateEvents:Bool = false;

    public var onClick:Null<UIEvent -> Void> = null;
    public var onOver:Null<UIEvent -> Void> = null;
    public var onOut:Null<UIEvent -> Void> = null;
    public var onPush:Null<UIEvent -> Void> = null;
    public var onRelease:Null<UIEvent -> Void> = null;
    public var onMove:Null<UIEvent -> Void> = null;
    public var onWheel:Null<UIEvent -> Void> = null;

    public function new(width:Float, height:Float, ?parent:UIObject) {
        super(parent);
        this.width = width;
        this.height = height;
    }

    public function focus():Void {}
    public function blur():Void {}
}

class UICamera2D {
    public var viewportScaleX:Float = 1.0;
    public var viewportScaleY:Float = 1.0;
    public var offsetX:Float = 0.0;
    public var offsetY:Float = 0.0;
    public function new() {}
    public function eventToCamera(e:UIEvent):Void {}
}

class UIScene2D extends UIObject {
    public var width:Int;
    public var height:Int;
    public var scaleMode:UIScaleMode = UIScaleMode.LetterBox(1280, 720);
    public var elapsedTime:Float = 0.0;
    public var offsetX:Float = 0.0;
    public var offsetY:Float = 0.0;
    public var viewportScaleX:Float = 1.0;
    public var viewportScaleY:Float = 1.0;
    public var camera:UICamera2D = new UICamera2D();
    public var interactiveCamera:Null<UICamera2D> = null;

    public function new(width:Int = 1280, height:Int = 720) {
        super(null);
        this.width = width;
        this.height = height;
    }

    public function setElapsedTime(dt:Float):Void {
        elapsedTime = dt;
    }

    public function checkResize():Void {}

    public function dispose():Void {
        removeChildren();
    }
}
