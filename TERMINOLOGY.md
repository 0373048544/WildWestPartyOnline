# Thuật ngữ gameplay chuẩn

- **Lượt hành động / action turn:** lượt của một người chơi, từ bắt đầu lượt đến khi chuyển sang người tiếp theo.
- **Vòng chơi / round:** một chu kỳ trong đó mọi người chơi còn sống và đang kết nối đều có một lượt hành động.
- **Ván chơi / match:** toàn bộ game từ lúc bắt đầu đến khi có kết quả.
- **Phản ứng / reaction:** lựa chọn xảy ra ngoài lượt hành động, chẳng hạn NÉ, Đấu súng hoặc Thổ dân.

## Phạm vi giới hạn lá bài

- BẮN: tối đa một lần mỗi lượt hành động; Willy/Volcanic có thể override. BẮN dùng trong phản ứng không tính giới hạn này.
- HOẢNG LOẠN: tối đa một lần mỗi lượt hành động; không có override.
- BỎ BÀI / Cat Balou: tối đa một lần mỗi lượt hành động; không có override.
- BÁCH HÓA: tối đa một lần cho mỗi người chơi trong cả ván chơi.
- CỬA HÀNG: tối đa một lần cho mỗi người chơi trong cả ván chơi.

Không dùng “lượt” một mình khi có thể nhầm với vòng chơi. Không đặt biến `used_this_round` cho state thực tế reset ở đầu lượt hành động.
