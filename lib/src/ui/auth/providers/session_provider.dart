import 'package:hodour/src/imports/imports.dart';
import 'package:hodour/src/data/models/user_model.dart';
import 'package:hodour/src/data/repositories/auth_repository.dart';
import 'package:hodour/src/data/repositories/auth_repository_impl.dart';

sealed class SessionState {
  const SessionState();
  AppUser? get userOrNull => switch (this) {
        SessionAuthenticated(:final user) => user,
        _ => null,
      };
}

final class SessionUnknown extends SessionState {
  const SessionUnknown();
}

final class SessionAuthenticated extends SessionState {
  const SessionAuthenticated(this.user,
      {this.profileRefresh = const RequestSuccess(null)});
  final AppUser user;
  final RequestState<void> profileRefresh;
}

final class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated();
}

final class SessionUnavailable extends SessionState {
  const SessionUnavailable(this.failure);
  final Failure failure;
}

SessionState sessionFromUser(AppUser? user) => switch (user) {
      final AppUser user => SessionAuthenticated(user),
      null => const SessionUnauthenticated(),
    };
final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepositoryImpl());
final sessionProvider = StateNotifierProvider<SessionNotifier, SessionState>(
    (ref) => SessionNotifier(repository: ref.read(authRepositoryProvider)));

class SessionNotifier extends StateNotifier<SessionState>
    with StreamSubscriptionsMixin {
  SessionNotifier({required AuthRepository repository})
      : _repository = repository,
        super(const SessionUnknown()) {
    addSubscription(_repository.onAuthStateChanged.listen((user) {
      _revision++;
      state = sessionFromUser(user);
    }));
    restore();
  }
  final AuthRepository _repository;
  int _revision = 0;
  bool _refreshInFlight = false;

  Future<void> restore() async {
    final revision = ++_revision;
    state = const SessionUnknown();
    final result = await _repository.checkAuthState();
    if (!mounted || revision != _revision) return;
    state = result.fold(
        (failure) => switch (failure) {
              ServerFailure(statusCode: 401) => const SessionUnauthenticated(),
              _ => SessionUnavailable(failure),
            },
        sessionFromUser);
  }

  Future<void> refresh() async {
    final current = state;
    if (current is! SessionAuthenticated || _refreshInFlight) {
      return;
    }
    final revision = ++_revision;
    _refreshInFlight = true;
    final Either<Failure, AppUser?> result;
    try {
      result = await _repository.checkAuthState();
    } finally {
      _refreshInFlight = false;
    }
    if (!mounted || revision != _revision) return;
    if (current.profileRefresh.isSuccess &&
        result.fold((_) => false, (user) => user == current.user)) {
      return;
    }
    state = result.fold(
      (failure) => switch (failure) {
        ServerFailure(statusCode: 401) => const SessionUnauthenticated(),
        _ => SessionAuthenticated(current.user,
            profileRefresh: RequestFailure(failure)),
      },
      sessionFromUser,
    );
  }

  @override
  void dispose() {
    cancelSubscriptions();
    super.dispose();
  }
}
