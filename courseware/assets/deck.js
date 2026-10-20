/* ==========================================================================
   deck.js — 放映器 v1.1(契约第 8 条)
   无依赖、离线可用(file:// 直接双击打开也没问题)
   键盘:← → 空格 Home End F N ?   /   滚轮上下 / 鼠标左右半边点击
   v1.1 修复:history.replaceState 在 file:// 下会抛异常,已加 try/catch
   ========================================================================== */
(function () {
  'use strict';

  var STAGE_W = 1920;
  var STAGE_H = 1080;

  var stage    = document.getElementById('stage');
  var slides   = Array.prototype.slice.call(document.querySelectorAll('.slide'));
  var progress = document.getElementById('progress');
  var pageno   = document.getElementById('pageno');
  var notesBox = document.getElementById('notes');
  var notesBody= notesBox ? notesBox.querySelector('.body') : null;
  var help     = document.getElementById('help');

  if (!stage || !slides.length) return;

  var index = 0;

  /* ---------- 舞台缩放:内容永不回流 ---------- */
  function fit() {
    var s = Math.min(window.innerWidth / STAGE_W, window.innerHeight / STAGE_H);
    stage.style.transform = 'translate(-50%, -50%) scale(' + s + ')';
  }
  window.addEventListener('resize', fit);
  fit();

  /* ---------- 翻页节流:防止一次滚动/点击连翻多页 ---------- */
  var LOCK_MS = 300;
  var lockedAt = 0;
  function lock()  { lockedAt = Date.now(); }
  function locked(){ return (Date.now() - lockedAt) < LOCK_MS; }

  function pad2(n) { return n < 10 ? '0' + n : String(n); }

  /* ---------- 渲染 ---------- */
  function render() {
    slides.forEach(function (el, i) {
      el.classList.toggle('is-active', i === index);
      if (i === index) {
        // 重放进场动效
        Array.prototype.forEach.call(el.querySelectorAll('[data-anim]'), function (n) {
          n.style.animation = 'none';
          void n.offsetHeight;          // 强制重排,让动画重新开始
          n.style.animation = '';
        });
      }
    });

    if (pageno)   pageno.textContent = pad2(index + 1) + ' / ' + pad2(slides.length);
    if (progress) progress.style.width = ((index + 1) / slides.length * 100) + '%';

    if (notesBody) {
      var aside = slides[index].querySelector('.notes');
      notesBody.textContent = aside ? aside.textContent.trim() : '(本页无备注)';
    }

    // file:// 下 Chrome 会禁止 replaceState,必须吞掉这个异常
    try {
      if (location.hash !== '#' + (index + 1)) {
        history.replaceState(null, '', '#' + (index + 1));
      }
    } catch (e) { /* file:// 下正常,忽略 */ }
  }

  function go(next) {
    if (next < 0 || next >= slides.length || next === index) return;
    index = next;
    render();
  }

  /* ---------- 键盘 ---------- */
  document.addEventListener('keydown', function (e) {
    switch (e.key) {
      case 'ArrowRight': case ' ': case 'PageDown': case 'Enter':
        e.preventDefault(); go(index + 1); break;
      case 'ArrowLeft': case 'PageUp': case 'Backspace':
        e.preventDefault(); go(index - 1); break;
      case 'Home': e.preventDefault(); go(0); break;
      case 'End':  e.preventDefault(); go(slides.length - 1); break;
      case 'f': case 'F':
        e.preventDefault();
        if (document.fullscreenElement) { document.exitFullscreen(); }
        else if (document.documentElement.requestFullscreen) {
          document.documentElement.requestFullscreen();
        }
        break;
      case 'n': case 'N':
        e.preventDefault();
        if (notesBox) notesBox.classList.toggle('is-open');
        break;
      case '?': case 'h': case 'H':
        e.preventDefault();
        if (help) help.classList.toggle('is-open');
        break;
    }
  });

  /* ---------- 滚轮翻页(累加 + 节流,兼容滚轮与触控板)---------- */
  var acc = 0, accTimer = null;

  function inPanel(node) {
    if (!node || !node.closest) return false;
    return !!node.closest('#notes, #help');
  }

  window.addEventListener('wheel', function (e) {
    if (inPanel(e.target)) return;

    acc += e.deltaY;
    if (accTimer) clearTimeout(accTimer);
    accTimer = setTimeout(function () { acc = 0; }, 200);

    if (locked()) return;
    if (Math.abs(acc) < 48) return;

    var dir = acc > 0 ? 1 : -1;
    acc = 0;
    lock();
    go(index + dir);
  }, { passive: true });

  /* ---------- 鼠标翻页:左 15% 上一页,其余下一页 ---------- */
  document.addEventListener('click', function (e) {
    if (inPanel(e.target)) return;
    if (locked()) return;
    lock();
    var ratio = e.clientX / window.innerWidth;
    go(index + (ratio < 0.15 ? -1 : 1));
  });

  /* ---------- 初始页:支持 lesson-01.html#7 直接跳页 ---------- */
  var h = parseInt((location.hash || '').replace('#', ''), 10);
  if (!isNaN(h) && h >= 1 && h <= slides.length) index = h - 1;

  render();
})();