import 'package:barcode_ml_kit/util/only_numbers.dart';

/// Classe utilitária para conversões de códigos de boleto bancário.
///
/// As regras de boleto utilizam [boleto-utils](https://github.dev/hfsnetbr/boleto-utils) como
/// referência assim como as regras da Febran explicadas pelo IBBA (https://www.bb.com.br/docs/pub/emp/empl/dwn/Doc5175Bloqueto.pdf).
class BillUtil {
  /// Dado um código [code] de boleto de 44 dígitos, retorna a linha digitável do boleto (código de 48
  /// dígitos no formato da Febraban).
  static String getFormattedbarcode(String code) {
    code = code.formatOnlyNumbers();
    assert(code.length == 44, "É necessário um código válido de 44 dígitos");

    return isConcessionary(code) ? _buildConcessionaryBarcode(code) : _buildBankBarcode(code);
  }

  /// Cálcula a linha digitável de um boleto comum.
  ///
  /// exemplo:       00199883600000010000000003406098001381742417
  /// deve retornar: 00190000090340609800813817424172988360000001000
  static String _buildBankBarcode(String rawCode) {
    String newCode = rawCode.substring(0, 4) +
        rawCode.substring(19) +
        rawCode.substring(4, 5) +
        rawCode.substring(5, 19);

    String block1 = newCode.substring(0, 9) + _mod10(newCode.substring(0, 9));
    String block2 = newCode.substring(9, 19) + _mod10(newCode.substring(9, 19));
    String block3 = newCode.substring(19, 29) + _mod10(newCode.substring(19, 29));
    String block4 = newCode.substring(29);

    return block1 + block2 + block3 + block4;
  }

  /// Cálcula a linha digitável de um boleto de concessionária.
  ///
  /// exemplo:       84650000000356802921000131250349092112195973
  /// deve retornar: 846500000001356802921003013125034903921121959735
  static String _buildConcessionaryBarcode(String rawCode) {
    String Function(String s) mod = _modRef(rawCode);

    String block1 = rawCode.substring(0, 11) + mod(rawCode.substring(0, 11));
    String block2 = rawCode.substring(11, 22) + mod(rawCode.substring(11, 22));
    String block3 = rawCode.substring(22, 33) + mod(rawCode.substring(22, 33));
    String block4 = rawCode.substring(33) + mod(rawCode.substring(33));

    return block1 + block2 + block3 + block4;
  }

  /// Retorna função para cálculo do módulo baseado no identificador referencia.
  static String Function(String v) _modRef(String code) {
    String char = code.substring(2, 3);
    if (char == '6' || char == '7') return _mod10;
    return _mod11;
  }

  /// Cálculo do módulo de 10
  static String _mod10(String code) {
    int factor = 2;
    int sum = code.split("").reversed.map((s) {
      int num = int.parse(s);
      final int digit = num * factor;
      factor = factor == 2 ? 1 : 2;
      return _minimizeNumber(digit);
    }).reduce((t, e) => t + e);

    final int mod = 10 - int.parse(sum.toString().split("").toList().last);
    return (mod == 10 ? 0 : mod).toString();
  }

  /// Cálculo do módulo de 11
  static String _mod11(String code) {
    const int factorMax = 9;
    int factor = 2;

    final int sum = code.split("").reversed.map((s) {
      int num = int.parse(s);
      final int digit = num * factor;
      factor = factor >= factorMax ? 2 : (factor + 1);
      return digit;
    }).reduce((t, e) => t + e);

    final int mod = sum % 11;
    return ((mod <= 1) ? 0 : (11 - mod)).toString();
  }

  /// Informa se o boleto é do tipo Concessionária; caso contrário, trata-se de banco.
  static bool isConcessionary(String barcode) => barcode.substring(0, 1) == '8';

  /// Operação recursiva que reduz um número até que ele possua apenas um algarismo
  static int _minimizeNumber(int sum) {
    if (sum <= 9) return sum;
    int result = sum.toString().split("").map((s) => int.parse(s)).reduce((a, b) => a + b);
    return result <= 9 ? result : _minimizeNumber(sum);
  }
}