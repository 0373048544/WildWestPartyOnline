# Miền Tây Đại Chiến

Project Godot 4.7.2, client Web + server Godot headless có thẩm quyền, giao diện tiếng Việt và saloon 3D tạo bằng primitive. Không dùng artwork bên ngoài. ENet được giữ cho kiểm thử desktop; giao diện người chơi mặc định dùng WebSocket và mã phòng.

## Web multiplayer cục bộ

Đã chuẩn bị build tại build/web. Khi server và web server đang chạy, mở:

    http://127.0.0.1:8080

Nhập tên → TẠO PHÒNG → sao chép mã 6 ký tự. Người khác mở cùng URL, nhập tên + mã → THAM GIA. Ready và Start diễn ra trong phòng chung. Không nhập IP hoặc cổng trong giao diện.

Tái tạo build (Godot 4.7.2 và Node 22+):

    node tools/fetch-web-templates.cjs
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/Export-Web.ps1 -Godot "C:/path/to/Godot_v4.7.2-stable_win64_console.exe"

Script tải chỉ lấy hai template Web không luồng từ bản phát hành chính thức, kiểm tra CRC của entry ZIP và lưu vào build/templates. Không cần cài template toàn nền tảng vào hồ sơ người dùng.

Chạy hai terminal tại thư mục project:

    godot --headless --path . server/DedicatedServer.tscn -- --development

    node tools/serve-web.cjs

Hoặc chạy tools/Run-Local-Web.ps1 -Godot "C:/path/to/Godot.exe" để khởi động hai tiến trình ẩn và in PID. Dừng đúng hai PID được in khi không cần nữa. Server mặc định chỉ lắng nghe 127.0.0.1:7000; HTTP chỉ lắng nghe 127.0.0.1:8080.

Mặc định 4–7 người; chỉ server có --development trong debug build mới cho phép đúng 2 người. Host là chủ phòng và có thể chuyển sang người đang kết nối khác; vai trò trong game được xáo riêng, không đổi khi chuyển chủ phòng.

Endpoint tập trung trong config/network.cfg (desktop client), web/network-config.js (Web), hoặc WWPO_SERVER_URL (desktop). HTTPS dùng WSS; cấu hình mẫu trỏ WSS cùng origin /ws để dùng với TLS reverse proxy sau này. Mốc hiện tại chỉ chạy local, chưa có triển khai cloud hay public.

Refresh tab khôi phục bằng sessionStorage của tab. Mất socket được giữ chỗ 45 giây; reconnect khôi phục đúng ID, tay bài, vai trò và nhân vật. Menu/đồng hồ server vẫn chạy. Sau thời gian chờ, áp dụng đường xử lý bỏ cuộc hiện có. Phiên và phòng lưu trong RAM, không phục hồi sau server restart.

Web export dùng Compatibility/WebGL 2, không bật threads hoặc extension native. Bản Web tắt bóng đèn hướng để giảm tải và có layout theo chiều màn hình. File WASM khoảng 38 MB trước nén HTTP; nên dùng compression khi chuẩn bị hosting sau này. Có thể xuất release bằng tools/Export-Web.ps1 -Release. Build sinh ra không đưa vào Git.

Chi tiết kiến trúc phòng, giao thức, riêng tư và khôi phục: [server/README.md](server/README.md).

## Chơi thử

Mở project.godot và nhấn F5 cũng chạy được client desktop kết nối cùng dedicated server. Tạo/tham gia bằng mã phòng giống bản Web.

HOST luôn vào PHÒNG CHỜ trước. Tất cả bấm sẵn sàng, chủ phòng bấm BẮT ĐẦU. Bình thường hỗ trợ 4–7 người; debug cho phép đúng 2 người. Không hỗ trợ 3 người. Host chỉ có quyền quản lý phòng, không được ưu tiên vai trò, máu hoặc lượt.

Mỗi ván server xáo vai trò và chia riêng hai lựa chọn nhân vật cho từng người. Chỉ khi mọi người chọn xong (hoặc hết 25 giây) nhân vật được công khai. Cảnh sát trưởng được chọn ngẫu nhiên mở lượt đầu. Chơi lại làm mới vai trò, lựa chọn nhân vật, bộ bài, tay bài và lượt.

Trong Godot, có thể dùng Debug > Customize Run Instances và chạy 4 client kết nối server chung. API host_game/join_game ENet vẫn còn cho test desktop cũ; UI chính không gọi API này. Người chơi browser không cần UDP, VPN hoặc port forwarding.

## Điều khiển trên bàn

- Tay bài là thành phần 2D chính. Bài xếp chồng nhẹ; rê chuột hoặc nhấn giữ khoảng 0,45 giây để xem mô tả đầy đủ. Nhấn giữ rồi thả không tự dùng bài.
- Chạm/nhấp lá Bắn, Hoảng loạn, Cat Balou, Đấu súng hoặc Nhà giam → các cao bồi hợp lệ sáng lên → chạm/nhấp trực tiếp cao bồi. Mũi tên cong xem trước và thông tin khoảng cách/tầm súng chỉ dùng dữ liệu công khai.
- Chạm lại lá đang chọn, nút × HỦY nhỏ cạnh tay, Esc hoặc chuột phải để hủy. Không có hàng nút chọn người chơi hoặc menu tên cho tấn công.
- Khi bị Bắn, Đấu súng, Thổ dân hoặc hấp hối: các lá đáp trả hợp lệ trên chính tay bài sáng lên. Chạm lá để trả lời hoặc chọn CHỊU ĐÒN/KHÔNG CỨU. Janet dùng cùng lá bài vật lý để đổi Bắn/Né theo ngữ cảnh.
- Sid khi thiếu máu có biểu tượng ✚ nhỏ cạnh tay bài. Chạm để chọn/bỏ chọn đúng hai lá, rồi chọn HỒI 1 MÁU. Không có nút kỹ năng lớn thường trực.
- Hoảng loạn/Cat Balou: sau khi chọn cao bồi, chạm vùng TAY KÍN (server chọn ngẫu nhiên, không lộ tên bài), vũ khí hoặc trang bị đang sáng trước ghế.
- Cửa hàng: bài ngửa xuất hiện giữa bàn; người đang có quyền chọn chạm lá muốn lấy. Những người khác chỉ xem.
- Jesse/Pedro chọn chồng rút/chồng bỏ trực tiếp trên bàn. Jesse cũng có thể chạm vùng tay kín của đối thủ. Rút đầu lượt bình thường hoàn toàn tự động.
- Bỏ bài cuối lượt: hiện BỎ X LÁ; chạm từng lá để bỏ. Server tự chuyển lượt khi đủ giới hạn theo máu.
- KẾT THÚC LƯỢT chỉ xuất hiện gần tay bài trong giai đoạn hành động của bạn.
- Chạm cao bồi khi không nhắm mục tiêu để xem thẻ thông tin: nhân vật, kỹ năng, máu, số bài, vũ khí, trang bị, khoảng cách và vai trò công khai. Chạm chỗ trống để đóng. Vai trò bí mật của đối thủ không hiện.
- Menu ☰ hoặc Esc khi không chọn bài mở TIẾP TỤC / LUẬT CHƠI / RỜI TRẬN. Đồng hồ và trận online vẫn tiếp tục trong menu.
- Nhật ký mặc định chỉ hiện hai hành động gần nhất, có thể mở rộng. Debug chỉ hiện cho host trong bản debug, nằm sau nút DEBUG ở menu tạm dừng.
- Game Over công khai vai trò; chỉ host được CHƠI LẠI hoặc VỀ PHÒNG CHỜ.

## Luật và dữ liệu hiện tại

RoleData hỗ trợ phân bố 4/5/6/7 người. Cảnh sát trưởng công khai, +1 máu; Phó cảnh sát, Tội phạm và Kẻ phản bội được gửi riêng. Vai trò được công khai khi chết và khi hết trận.

CharacterData nạp 16 nhân vật từ resources/characters/characters.json, gồm các kỹ năng rút bài, đổi Bắn/Né, khoảng cách, hai lần Né, hồi máu, nhặt bài khi chết và không giới hạn Bắn. Chọn nhân vật và các lựa chọn kín được gửi riêng cho người sở hữu.

Bộ bài 80 lá có định nghĩa và số lượng trong resources/cards/definitions.json và base_deck.json. Có Bắn, Né, Rượu, Hoảng loạn, Cat Balou, Đấu súng, Nhà giam, năm vũ khí, Thùng, Ngựa, Ống nhòm, Tiếp tế, Cửa hàng, Thổ dân, Thuốc nổ, Súng liên thanh, Quán rượu và Wells Fargo.

**Chất/số hiện là cấu hình prototype cố định, chưa đối chiếu chính xác từng lá của bản in gốc.** Không random chất/số mỗi ván. File base_deck.json ghi rõ trạng thái này; muốn khớp chính xác bộ gốc cần thay các entry và giữ kiểm tra tổng 80 lá. tools/generate_base_data.py có thể tái tạo dữ liệu prototype nếu máy có Python.

Tay đầu bằng máu tối đa của nhân vật, gồm thưởng Cảnh sát trưởng. Rút hai mỗi lượt trừ kỹ năng. Bình thường chỉ một lá Bắn trong giai đoạn hành động; dùng sai mục tiêu không tiêu giới hạn. Volcanic/Willy cho bắn nhiều; đáp trả Đấu súng/Thổ dân không tiêu giới hạn. Bắn chuyển đổi của Janet có tiêu giới hạn khi tấn công.

Khoảng cách vòng bỏ qua người chết; Ngựa/Paul và Ống nhòm/Rose cộng dồn. Vũ khí chỉ tăng tầm, không thay khoảng cách. Rượu không hồi khi chỉ còn hai người; sát thương chết người có thể cần nhiều Rượu. Thuốc nổ được phán định trước Nhà giam. Server quản lý hàng đợi phản ứng, giới hạn thời gian và mọi lựa chọn.

## Kiến trúc

- autoload/NetworkManager.gd: facade client/desktop debug, snapshot và sự kiện; WebSocket dùng RoomClient/NetworkTransport, ENet dùng adapter debug.
- server/DedicatedServer.gd và RoomBridge.gd: danh bạ phòng/phiên, host, khôi phục, mỗi phòng có GameManager độc lập dùng chung luật. Server không phải người chơi.
- scripts/network/: WebSocketTransport, ENetTransport, RoomProtocol, NetworkConfig và RoomClient. JSON STATE gửi riêng từng connection với public + private đúng người trong cùng revision.
- autoload/GameManager.gd: match lifecycle, lượt, ý định hợp lệ, máu/chết/thắng và snapshot.
- scripts/game/RoleData.gd, CharacterSelection.gd, AbilityResolver.gd, DrawPhaseResolver.gd, RulesFlow.gd: phân vai, chọn nhân vật, kỹ năng, rút bài, hàng đợi phản ứng/phán định.
- scripts/ui/App.gd: menu/phòng chờ và điều phối. MatchHUD.gd: HUD gọn, tay bài, phản ứng theo ngữ cảnh và menu tạm dừng.
- scripts/ui/HandFan.gd và CardView.gd / scenes/ui/CardUI.tscn: bài xếp chồng, chọn, xem trước và nhấn giữ.
- scripts/ui/TargetingController.gd, TargetingArrow.gd: Area3D ray picking, chuột/chạm, mũi tên và hủy.
- scripts/game/TableView.gd, TableObjects.gd và TableObject.gd: avatar, trạng thái gọn trong 3D, vùng tay kín/trang bị, chồng rút/bỏ và bài Cửa hàng.
- scripts/vfx/TableEffects.gd: bài bay, phán định, chớp súng, −N máu, +1, bụi, BOOM; hiệu ứng tự dọn.
- scripts/game/SaloonRoom.gd, SaloonLantern.gd, scripts/player/PlayerAvatar.gd: môi trường/cao bồi procedural.
- localization/vi.gd: bản dịch. Font hệ thống Segoe UI / Arial / DejaVu Sans và fallback.

UX không thay đổi luật. Client chỉ gửi ID lá bài/người chơi, lựa chọn có request ID hoặc hai ID bài cho Sid. Máy chủ xác thực lại. Vùng tay kín chỉ mang player ID + zone, không chứa lá bài bí mật. Sự kiện VFX chỉ gửi count, player ID và bài đã công khai (bỏ/phán định/Cửa hàng), không truyền tay bài kín hoặc lựa chọn nhân vật.

Dedicated server là bên tin cậy. Host browser chỉ có dữ liệu của một người chơi, không giữ registry luật, tay bài đối thủ hay deck order. Session token 256 bit chỉ gửi cho connection sở hữu, lưu trong sessionStorage của tab và không nằm trong public state. ENet debug vẫn có host desktop tin cậy; đó không phải đường chơi Web.

## Kiểm thử

Các lệnh sau không cần framework ngoài:

    godot --headless --path . tests/RulesTest.tscn
    godot --headless --path . tests/TargetingTest.tscn
    godot --headless --path . tests/GameplayUXTest.tscn
    godot --headless --path . tests/LocalizationTest.tscn
    godot --headless --path . tests/PresentationTest.tscn
    godot --headless --path . tests/VisualEffectsTest.tscn

RulesTest kiểm tra 1.934 điều kiện, gồm 100 lần phân vai cho từng cấu hình 4–7 người, kỹ năng, bài, thưởng/phạt, thắng và riêng tư. GameplayUXTest kiểm tra trực tiếp tay bài, Janet, Sid, lựa chọn trên bàn, menu, preview và ngăn chọn ngoài lượt. TargetingTest dùng sự kiện chuột/chạm thực qua ray picking 3D.

Có thể thêm -- --capture khi chạy không headless với GameplayUXTest, TargetingTest, LocalizationTest hoặc VisualEffectsTest để lưu ảnh cục bộ vào tests/artifacts (bỏ qua bởi Git và Godot importer).

Test nhiều tiến trình ENet trên Windows (cổng 17070):

    powershell -NoProfile -ExecutionPolicy Bypass -File tests/RunNetworkTest.ps1 -Godot "C:/path/to/Godot_v4.7.2-stable_win64_console.exe" -ProcessCount 4

Dùng -ProcessCount 8 để chạy 7 người + kiểm tra người thứ tám bị từ chối. Test phòng chờ hai người trên cổng 7000:

    powershell -NoProfile -ExecutionPolicy Bypass -File tests/RunNetworkTest.ps1 -Godot "C:/path/to/Godot_v4.7.2-stable_win64_console.exe" -TestScene tests/LobbyTest.tscn -ProcessCount 2

Test mạng có thể cần quyền firewall/chạy tiến trình. Test headless trong sandbox có thể in cảnh báo Windows certificate store; game dùng ENet, không dùng TLS. Kết quả PASS và lỗi GDScript cần được xem riêng với cảnh báo môi trường này.

Kiểm thử dedicated server đang chạy và HTTP Web:

    node tests/web/protocol-test.cjs
    node tests/web/room-capacity-test.cjs
    node tests/web/browser-test.cjs
    node tests/web/browser-test.cjs --mobile

Hai test đầu dùng WebSocket thực: tạo/join, cách ly phòng, ready, quyền host, private choices/hands, reconnect, chuyển host, đủ 7 người, từ chối người thứ tám và dọn phòng rỗng. Browser test chạy hai context Edge tách biệt bằng DevTools, không cần npm dependency, thao tác vào UI và 3D thật. --mobile bật giả lập màn hình ngang điện thoại và sự kiện touch, không chỉ gửi chuột. Có thể đặt WWPO_BROWSER để chọn executable Chrome/Edge. Ảnh lưu tests/artifacts/web.

BrowserTestBridge chỉ được bật trong Web DEBUG khi URL có ?e2e=1; dữ liệu quan sát chỉ là dữ liệu browser đang sở hữu/nhìn thấy, không có token, server registry hoặc tay đối thủ. Release build không tạo bridge.

## Giới hạn / TODO

- Đã xuất và chạy bản Web trên Chromium/Edge desktop và giả lập touch. Chưa kiểm thử Firefox, Safari/iPhone hoặc Android thật; vẫn cần kiểm thử thiết bị thực và tab chạy nền.
- Bài nhiều xếp chồng sát hơn; tay bài cực lớn có thể khó chạm chọn, nên bổ sung phân trang/zoom trên màn hình nhỏ.
- Chưa có âm thanh. Có presentation_feedback để gắn âm thanh nút; toàn bộ art/props hiện là mesh và nét vẽ gốc.
- Phán định dùng bài dựng 3D; hiệu ứng không chặn hay kéo dài thời gian xử lý phía server.
- Có reconnect 45 giây và chuyển quyền chủ phòng; chưa có lưu bền qua server restart, spectator joining, save game hay matchmaking. Rời phòng chủ động là bỏ cuộc.
- Các lựa chọn riêng phức tạp như Kit Carlson / Lucky Duke vẫn dùng khung chọn bài riêng; các phản ứng chiến đấu dùng trực tiếp tay bài.
- Chưa đối chiếu chất/số với bộ bài in gốc. Không tuyên bố tương thích chính xác mọi FAQ/phiên bản của trò gốc.
- Chưa triển khai public. Cần TLS termination/WSS, chính sách origin và vận hành trước bước hosting; xem tài liệu server. Bộ bài/nhân vật/luật không được mở rộng trong lần chuyển nền tảng này.

