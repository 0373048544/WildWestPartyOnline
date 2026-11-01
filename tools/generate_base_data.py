"""Rebuild base data using the reviewed official 80-card rank/suit manifest."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
cards = [
("shoot","BẮN","Tấn công trong tầm súng. Bình thường chỉ 1 lá mỗi lượt.",0,1,0,1,25,"weapon"),
("dodge","NÉ","Đáp trả một hiệu ứng Bắn. Janet có thể đổi thành Bắn.",3,0,1,1,12,"none"),
("drink","UỐNG RƯỢU","Hồi 1 máu; cứu mạng khi hấp hối. Không có tác dụng khi chỉ còn 2 người.",0,0,2,1,6,"none"),
("panic","HOẢNG LOẠN","Lấy 1 lá trên tay hoặc đang đặt trước người cách bạn tối đa 1.",0,1,5,1,4,"distance_one"),
("cat_balou","CAT BALOU","Bỏ 1 lá trên tay hoặc đang đặt trước bất kỳ đối thủ nào.",0,1,4,1,4,"any"),
("showdown","ĐẤU SÚNG","Luân phiên bỏ lá Bắn. Người không đáp trả mất 1 máu.",0,1,8,1,3,"any"),
("jail","NHÀ GIAM","Giam một đối thủ không phải Cảnh sát trưởng. Lật Cơ để thoát, nếu không mất lượt.",2,1,13,1,3,"any"),
("schofield","SCHOFIELD","Vũ khí tầm 2. Thay thế vũ khí hiện tại.",1,0,6,2,3,"none"),
("barrel","THÙNG MAY MẮN","Khi bị Bắn, lật bài: Cơ tính là một lần Né.",2,0,7,1,2,"none"),
("horse","NGỰA MUSTANG","Đối thủ tính khoảng cách đến bạn tăng 1.",2,0,7,1,2,"none"),
("volcanic","VOLCANIC","Tầm 1. Được dùng không giới hạn lá Bắn trong lượt.",1,0,6,1,2,"none"),
("supply","TIẾP TẾ","Rút 2 lá bài.",0,0,3,2,2,"none"),
("general_store","CỬA HÀNG","Lật bài theo số người sống. Mỗi người chọn 1, bắt đầu từ bạn.",0,0,10,1,2,"none"),
("indians","THỔ DÂN","Mỗi đối thủ bỏ 1 lá Bắn hoặc mất 1 máu. Không dùng Thùng để né.",0,2,12,1,2,"none"),
("dynamite","THUỐC NỔ","Đầu lượt lật Bích 2–9: mất 3 máu. Nếu không, chuyển người kế tiếp.",2,0,14,3,1,"none"),
("spyglass","ỐNG NHÒM","Khoảng cách từ bạn đến người khác giảm 1 (tối thiểu 1).",2,0,7,1,1,"none"),
("remington","REMINGTON","Vũ khí tầm 3.",1,0,6,3,1,"none"),
("carabine","REV. CARABINE","Vũ khí tầm 4.",1,0,6,4,1,"none"),
("winchester","WINCHESTER","Vũ khí tầm 5.",1,0,6,5,1,"none"),
("gatling","SÚNG LIÊN THANH","Bắn tất cả đối thủ, bỏ qua khoảng cách. Không tính vào giới hạn Bắn.",0,2,11,1,1,"none"),
("saloon","QUÁN RƯỢU","Tất cả người sống hồi 1 máu. Không dùng để cứu mạng khi hấp hối.",0,0,9,1,1,"none"),
("wells_fargo","WELLS FARGO","Rút 3 lá bài.",0,0,3,3,1,"none"),
]
definitions = {}
manifest = json.loads((ROOT / "resources/cards/base_manifest.json").read_text(encoding="utf-8"))
deck = []
for key,name,desc,typ,target,effect,amount,count,rng in cards:
    definitions[key] = dict(id=key,name=name,description=desc,type=typ,target=target,
        effect=effect,amount=amount,count=count,range_rule=rng,weapon_range=amount if typ==1 else 1)
    assert len(manifest["cards"][key]) == count, key
    for pair in manifest["cards"][key]:
        rank, suit = pair.split(":")
        deck.append(dict(card_data_id=key,suit=suit,rank=rank))
assert len(deck) == 80
characters = [
("bart_cassidy","Bart Cassidy",4,"damage_draw","Mỗi máu mất đi: rút 1 lá, kể cả do Thuốc nổ."),
("black_jack","Black Jack",4,"draw_reveal","Lộ lá rút thứ hai; nếu Cơ hoặc Rô thì rút thêm 1 lá kín."),
("calamity_janet","Calamity Janet",4,"convert","Đổi Bắn thành Né và ngược lại, kể cả khi đáp trả."),
("el_gringo","El Gringo",3,"damage_steal","Mỗi máu mất do người khác: lấy ngẫu nhiên 1 lá trên tay người đó."),
("jesse_jones","Jesse Jones",4,"draw_steal","Lá rút đầu có thể lấy ngẫu nhiên từ tay đối thủ; lá thứ hai rút từ chồng."),
("jourdonnais","Jourdonnais",4,"innate_barrel","Có sẵn hiệu ứng Thùng. Cộng thêm một lần lật nếu trang bị Thùng thật."),
("kit_carlson","Kit Carlson",4,"draw_choose","Xem 3 lá, chọn 2 để giữ; trả lá còn lại lên đầu chồng."),
("lucky_duke","Lucky Duke",4,"judge_choose","Mỗi lần phán định: lật 2 lá và chọn kết quả, bỏ cả hai."),
("paul_regret","Paul Regret",3,"distance_defense","Người khác thấy bạn xa hơn 1; cộng dồn với Ngựa."),
("pedro_ramirez","Pedro Ramirez",4,"draw_discard","Lá rút đầu có thể lấy từ đầu chồng bỏ; lá thứ hai từ chồng rút."),
("rose_doolan","Rose Doolan",4,"distance_sight","Thấy người khác gần hơn 1; cộng dồn với Ống nhòm."),
("sid_ketchum","Sid Ketchum",4,"discard_heal","Chọn bỏ đúng 2 lá trên tay để hồi 1 máu, kể cả khi hấp hối."),
("slab_the_killer","Slab the Killer",4,"double_dodge","Đối thủ cần 2 lần Né để tránh lá Bắn của bạn."),
("suzy_lafayette","Suzy Lafayette",4,"empty_draw","Khi hết bài trên tay, lập tức rút 1 lá."),
("vulture_sam","Vulture Sam",4,"death_collect","Khi người khác chết, thu toàn bộ bài trên tay và trang bị của họ vào tay."),
("willy_the_kid","Willy the Kid",4,"unlimited_shoot","Dùng không giới hạn lá Bắn trong lượt; vẫn tuân thủ tầm súng."),
]
def save(path,data):
    dest=ROOT/path
    dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
save("resources/cards/definitions.json",definitions)
save("resources/cards/base_deck.json",dict(expected_count=80,
    suit_rank_status="canonical_official_base",source=manifest["source"],cards=deck))
save("resources/characters/characters.json",[dict(character_id=i,display_name=n,max_hp=h,ability_id=a,ability_description_vi=d) for i,n,h,a,d in characters])
