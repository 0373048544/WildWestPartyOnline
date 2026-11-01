extends Node

func _ready() -> void:
	if not OS.has_feature("web"):
		return
	get_viewport().size_changed.connect(resize)
	resize()

func resize() -> void:
	var width: int = int(JavaScriptBridge.eval("window.innerWidth"))
	var height: int = int(JavaScriptBridge.eval("window.innerHeight"))
	var target := Vector2i(960, maxi(440,int(960.0*height/maxi(1,width)))) if width >= height else Vector2i(600,int(600.0*height/maxi(1,width)))
	if width > 1100:
		target = Vector2i(1440,int(1440.0*height/maxi(1,width)))
	if get_window().content_scale_size != target:
		get_window().content_scale_size = target
	get_viewport().set_meta("match_css_size",Vector2(width,height))
	# Read CSS env() through a temporary invisible element, not user-agent detection.
	var encoded: Variant = JavaScriptBridge.eval("""JSON.stringify((()=>{
const p=document.createElement('div');
p.style.cssText='position:fixed;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)';
document.body.appendChild(p);const s=getComputedStyle(p);
const result=[parseFloat(s.paddingLeft)||0,parseFloat(s.paddingTop)||0,parseFloat(s.paddingRight)||0,parseFloat(s.paddingBottom)||0];p.remove();return result;
})())""")
	var padding: Variant = JSON.parse_string(str(encoded))
	if padding is Array and padding.size()==4:
		var sx: float = float(target.x)/maxi(1,width)
		var sy: float = float(target.y)/maxi(1,height)
		var insets := Vector4(padding[0]*sx,padding[1]*sy,padding[2]*sx,padding[3]*sy)
		var previous: Vector4 = get_viewport().get_meta("match_safe_insets",Vector4.ZERO)
		get_viewport().set_meta("match_safe_insets",insets)
		if previous != insets and get_parent().has_method("refresh_layout"):
			get_parent().call_deferred("refresh_layout")
