import { Clarinet, Tx, Chain, Account, types } from '@stacks/transactions';
import { assertEquals } from 'chai';

Clarinet.test({
  name: "Ensures user can register",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const wallet_1 = accounts.get("wallet_1")!;

    let block = chain.mineBlock([
      Tx.contractCall("microvault-dao", "register-user", [], wallet_1.address)
    ]);

    assertEquals(block.receipts[0].result.expectOk(), true);
  },
});

Clarinet.test({
  name: "Can request loan with sufficient credit score",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const wallet_1 = accounts.get("wallet_1")!;

    let block = chain.mineBlock([
      Tx.contractCall("microvault-dao", "register-user", [], wallet_1.address),
      Tx.contractCall("microvault-dao", "request-loan", [types.uint(1000)], wallet_1.address)
    ]);

    assertEquals(block.receipts[1].result.expectOk(), true);
  },
});

Clarinet.test({
  name: "Can repay loan successfully",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const wallet_1 = accounts.get("wallet_1")!;

    let block = chain.mineBlock([
      Tx.contractCall("microvault-dao", "register-user", [], wallet_1.address),
      Tx.contractCall("microvault-dao", "request-loan", [types.uint(1000)], wallet_1.address),
      Tx.contractCall("microvault-dao", "repay-loan", [types.uint(1)], wallet_1.address)
    ]);

    assertEquals(block.receipts[2].result.expectOk(), true);
  },
});

Clarinet.test({
  name: "Only owner can update minimum credit score",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;

    let block = chain.mineBlock([
      Tx.contractCall("microvault-dao", "update-min-credit-score", [types.uint(600)], deployer.address)
    ]);

    assertEquals(block.receipts[0].result.expectOk(), true);
  },
});

Clarinet.test({
  name: "Can retrieve user data",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const wallet_1 = accounts.get("wallet_1")!;

    let block = chain.mineBlock([
      Tx.contractCall("microvault-dao", "register-user", [], wallet_1.address),
      Tx.contractCall("microvault-dao", "get-user-data", [types.principal(wallet_1.address)], wallet_1.address)
    ]);

    assertEquals(block.receipts[1].result.expectSome(), true);
  },
});
