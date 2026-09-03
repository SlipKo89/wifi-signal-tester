const String kKeeneticAlphaModel = 'Runner 4G (KN-2212)';
const String kKeeneticAlphaRelease = '5.01.C.3.0-1';

bool isVerifiedKeeneticAlpha({String? model, String? release}) =>
    model == kKeeneticAlphaModel && release == kKeeneticAlphaRelease;
