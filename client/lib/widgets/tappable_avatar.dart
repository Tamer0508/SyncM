import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Аватар, который по нажатию разворачивается на весь экран.
///
/// Переход построен на Hero: изображение физически то же самое, оно плавно
/// перетекает из круга в полноэкранный вид. Это читается как «приблизили ту
/// же картинку», а не «открылся другой экран» — и заодно объясняет, откуда
/// изображение взялось и куда вернётся при закрытии.
///
/// В развёрнутом виде доступны масштабирование щипком и закрытие свайпом вниз.
class TappableAvatar extends StatelessWidget {
  const TappableAvatar({
    super.key,
    required this.imageUrl,
    required this.radius,
    this.heroTag,
    this.fallbackIcon = Icons.person_rounded,
    this.showRing = false,
    this.title,
  });

  final String? imageUrl;
  final double radius;

  /// Метка Hero. Нужна, когда на экране несколько аватаров: одинаковые метки
  /// заставят Flutter анимировать не тот элемент.
  final Object? heroTag;

  final IconData fallbackIcon;
  final bool showRing;

  /// Подпись под изображением в развёрнутом виде — обычно имя пользователя.
  final String? title;

  bool get _hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  /// Одна или две первые буквы имени.
  static String _initialsOf(String? name) {
    final text = (name ?? '').trim();
    if (text.isEmpty) return '';

    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '';
    if (words.length == 1) return words.first.characters.first.toUpperCase();

    // characters, а не подстрока: у эмодзи и составных символов первый
    // «символ» строки — лишь часть знака, и обрезка даёт мусор на экране.
    return (words[0].characters.first + words[1].characters.first).toUpperCase();
  }

  /// Устойчивый цвет подложки по имени.
  static Color _colorFor(String? name, ColorScheme colors) {
    final palette = [
      colors.primaryContainer,
      colors.secondaryContainer,
      colors.tertiaryContainer,
    ];
    final text = name ?? '';
    if (text.isEmpty) return palette.first;

    // Сумма кодов символов, а не hashCode: hashCode в Dart не гарантирует
    // одинаковых значений между запусками, и цвет аватара менялся бы после
    // каждого перезапуска приложения.
    var sum = 0;
    for (final unit in text.codeUnits) {
      sum = (sum + unit) % 1000;
    }
    return palette[sum % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tag = heroTag ?? imageUrl ?? 'avatar';

    // Инициалы вместо безликой иконки.
    //
    // У человека без фотографии одинаковый серый силуэт, и в списке из
    // двадцати друзей такие строки различаются только подписью. Инициалы
    // читаются мгновенно, а цвет подложки выводится из имени — один и тот
    // же человек всегда одного цвета, и это работает как опознавательный
    // знак ещё до чтения текста.
    final initials = _initialsOf(title);
    final tint = initials.isEmpty ? colors.primaryContainer : _colorFor(title, colors);

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: tint,
      backgroundImage: _hasImage ? CachedNetworkImageProvider(imageUrl!) : null,
      child: _hasImage
          ? null
          : (initials.isEmpty
              ? Icon(fallbackIcon, size: radius, color: colors.onPrimaryContainer)
              : Text(
                  initials,
                  style: TextStyle(
                    // Размер от радиуса: у аватара 16 и 60 точек подпись
                    // должна занимать одинаковую долю круга.
                    fontSize: radius * 0.8,
                    fontWeight: FontWeight.w700,
                    color: colors.onPrimaryContainer,
                  ),
                )),
    );

    if (showRing) {
      avatar = Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.primary.withValues(alpha: 0.35), width: 2),
        ),
        child: avatar,
      );
    }

    // Без изображения разворачивать нечего — оставляем обычный аватар,
    // чтобы нажатие не открывало пустой экран с заглушкой.
    if (!_hasImage) return avatar;

    return GestureDetector(
      onTap: () => _open(context, tag),
      child: Hero(
        tag: tag,
        // flightShuttleBuilder: во время перелёта показываем прямоугольное
        // изображение без обрезки в круг. Иначе круглая маска сохранялась бы
        // до конца анимации и картинка «раскрывалась» скачком в самом конце.
        flightShuttleBuilder: (context, animation, direction, from, to) {
          return _FlightImage(imageUrl: imageUrl!, animation: animation);
        },
        child: avatar,
      ),
    );
  }

  void _open(BuildContext context, Object tag) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        // Прозрачный маршрут: фон предыдущего экрана виден, пока изображение
        // летит на своё место.
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.86),
        transitionDuration: AppMotion.medium,
        reverseTransitionDuration: AppMotion.short,
        pageBuilder: (_, animation, __) => _AvatarViewer(
          imageUrl: imageUrl!,
          heroTag: tag,
          title: title,
          animation: animation,
        ),
      ),
    );
  }
}

class _FlightImage extends StatelessWidget {
  const _FlightImage({required this.imageUrl, required this.animation});

  final String imageUrl;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // Скругление плавно уходит от круга к почти прямоугольнику по мере
        // разворачивания — переход получается непрерывным.
        final t = Curves.easeInOut.transform(animation.value);
        return ClipRRect(
          borderRadius: BorderRadius.circular(1000 * (1 - t) + AppRadius.lg * t),
          child: CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover),
        );
      },
    );
  }
}

class _AvatarViewer extends StatefulWidget {
  const _AvatarViewer({
    required this.imageUrl,
    required this.heroTag,
    required this.animation,
    this.title,
  });

  final String imageUrl;
  final Object heroTag;
  final String? title;
  final Animation<double> animation;

  @override
  State<_AvatarViewer> createState() => _AvatarViewerState();
}

class _AvatarViewerState extends State<_AvatarViewer> {
  // Смещение при свайпе вниз. Пока палец на экране, картинка следует за ним —
  // жест ощущается как «стягивание», а не как кнопка закрытия.
  double _dragOffset = 0;

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() => _dragOffset += details.delta.dy);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    // Закрываем либо при заметном смещении, либо при быстром движении —
    // короткий резкий свайп тоже должен срабатывать.
    if (_dragOffset > 120 || velocity > 700) {
      Navigator.of(context).pop();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;
    // Чем дальше утянули вниз, тем прозрачнее фон — видно, что жест работает.
    final dragProgress = (_dragOffset.abs() / 300).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        // HitTestBehavior.opaque обязателен. По умолчанию GestureDetector
        // работает в режиме deferToChild — реагирует только там, где есть
        // содержимое. Изображение отцентровано, вокруг него пустота, и
        // нажатия в эту пустоту до обработчика попросту не доходили:
        // закрыть просмотр щелчком мимо картинки было невозможно.
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 1 - dragProgress,
                child: Center(
                  child: Transform.translate(
                    offset: Offset(0, _dragOffset),
                    child: Hero(
                      tag: widget.heroTag,
                      // Поглощаем нажатия на самом изображении: здесь работает
                      // масштабирование щипком, и случайное касание при
                      // разведении пальцев не должно закрывать просмотр.
                      // Закрытие остаётся на пустой области, крестике и свайпе.
                      child: GestureDetector(
                        onTap: () {},
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: ClipRRect(
                            borderRadius: AppRadius.large,
                            child: CachedNetworkImage(
                              imageUrl: widget.imageUrl,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => const SizedBox(
                                width: 64,
                                height: 64,
                                child: Center(child: CircularProgressIndicator()),
                              ),
                              errorWidget: (_, __, ___) => const Icon(
                                Icons.broken_image_rounded,
                                size: 64,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.title != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Opacity(
                    opacity: 1 - dragProgress,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        widget.title!,
                        textAlign: TextAlign.center,
                        style: texts.titleMedium?.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.white,
                  tooltip: 'Закрыть',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}