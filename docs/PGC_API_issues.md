# PDL::Graphics::Cairo — API Issues & Decisions

このファイルは API 設計上の問題点、決定事項、既知の挙動を記録する。

---

## 解決済み

### #1 保存時フルデータ描画 (P:G:C07, 2026-06-12, commit 8447420)

**問題:** `_handle_savereq` が `render` コールバックを呼ぶ際、保存か表示かを区別できなかった。
`step_max=5`（200Hz相当）で妥協していた。

**解決:** `render` コールバックの第4引数に `$opts` hashref を追加。
保存時は `{is_save => 1}` が渡される。

```perl
render => sub {
    my ($state, $w, $h, $opts) = @_;
    my $is_save = $opts && $opts->{is_save};
    my $step = $is_save ? 1 : $step_display;  # 保存時は最高品質
    ...
};
```

通常描画時は `{}` が渡される（既存の `($state)` のみのコールバックも動作する）。

---

### #3 subplots API 一貫性 (P:G:C07, 2026-06-12, commit 9d51a51)

**問題:** 戻り値の構造が行数・列数で変わり、作った本人でも3回以上ミスした。

| 呼び出し | 旧戻り値 |
|---|---|
| `subplots(1,1)` | `($fig, $ax)` |
| `subplots(1,N)` | `($fig, $ax0, $ax1, ...)` フラット |
| `subplots(N,1)` | `($fig, $ax0, $ax1, ...)` フラット |
| `subplots(M,N)` | `($fig, \@row0, \@row1, ...)` ArrayRef |

**解決:** `$fig->ax()` アクセサを追加。構造を気にせずアクセスできる。

```perl
# 線形インデックス (matplotlib の axes.flat[i] 相当)
$fig->ax(0)->line(...);
$fig->ax(5)->line(...);

# (row, col) インデックス 0-based (matplotlib の axes[r,c] 相当)
$fig->ax(1, 2)->line(...);

# EEG チャンネルループの典型パターン
my ($fig, @ax) = subplots($nrows, $ncols, width => 1200, height => 800);
for my $i (0 .. $nchan-1) {
    $fig->ax($i)->line($t, $eeg->slice(",($i)"));
}
```

戻り値の構造（フラット vs ArrayRef）は変更なし。既存コードは壊れない。

---

### #4 add_subplot の欠如 (P:G:C07, 2026-06-12, commit 8447420)

**問題:** matplotlib ユーザーが必ず試す `$fig->add_subplot(R, C, idx)` がなくエラーになっていた。

**解決:** `subplot()` への委譲エイリアスとして実装。1-based idx。

```perl
my $ax = $fig->add_subplot(2, 3, 4);  # 2x3グリッドの4番目(1-based)
```

---

### #5 yticks 降順スキップバグ (P:G:C06, commit c84b2e7)

**問題:** `next if $yp > $mb - 2;` が最下tick以外をスキップしていた。

**解決:** 絶対値ギャップチェックに修正。

---

## 既知の挙動・注意事項

### subplots のサイズ指定

`subplots()` は内部で `Figure->new` を呼ぶ。`Driver::GS->new(height=>N)` とは独立している。
高さを指定しないとデフォルト 800×600 が使われる。

```perl
# 正しい
my ($fig, @ax) = subplots(8, 1, height => 1200);

# 間違い（GSドライバのサイズはFigureに伝わらない）
my $drv = PDL::Graphics::Cairo::Driver::GS->new(height => 1200);
my ($fig, @ax) = subplots(8, 1);  # 600px になる
```

### subplots(N, 1) での真っ青問題

別スレ(ac9c45e6)で報告されたが現在は再現せず。
`show_interactive` + render 内で `subplots` を呼んでいた場合の条件依存の可能性あり。
再現した場合は render 内の figure 生成を疑うこと。

---

## 未解決・保留

### #3 subplots 戻り値の破壊的統一（保留）

案A（常にフラット）は破壊的変更になるため CPAN リリース前に要検討。
現状は `$fig->ax()` アクセサで実用上は解決済み。
