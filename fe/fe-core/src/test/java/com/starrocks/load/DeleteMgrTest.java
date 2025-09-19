// Copyright 2021-present StarRocks, Inc. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package com.starrocks.load;

import com.starrocks.catalog.Column;
import com.starrocks.catalog.Database;
import com.starrocks.catalog.Partition;
import com.starrocks.catalog.Table;
import com.starrocks.common.FeConstants;
import com.starrocks.common.jmockit.Deencapsulation;
import com.starrocks.lake.delete.LakeDeleteJob;
import com.starrocks.qe.ConnectContext;
import com.starrocks.server.GlobalStateMgr;
import com.starrocks.server.RunMode;
import com.starrocks.sql.ast.DeleteStmt;
import com.starrocks.sql.ast.expression.TableName;
import com.starrocks.system.ComputeNode;
import com.starrocks.system.SystemInfoService;
import com.starrocks.utframe.StarRocksAssert;
import com.starrocks.utframe.UtFrameUtils;
import mockit.Mock;
import mockit.MockUp;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

public class DeleteMgrTest {

    @BeforeAll
    public static void beforeClass() {
        FeConstants.runningUnitTest = true;
        UtFrameUtils.createMinStarRocksCluster(true, RunMode.SHARED_DATA);
        GlobalStateMgr.getCurrentState().getTabletStatMgr().setStop();
        GlobalStateMgr.getCurrentState().getStarMgrMetaSyncer().setStop();
        SystemInfoService systemInfoService = GlobalStateMgr.getCurrentState().getNodeMgr().getClusterInfo();
        for (ComputeNode node : systemInfoService.getBackends()) {
            node.setAlive(true);
        }
        for (ComputeNode node : systemInfoService.getComputeNodes()) {
            node.setAlive(true);
        }
    }

    @Test
    public void testDeleteConditionsColumnIdAfterRename() {
        ConnectContext ctx = UtFrameUtils.createDefaultCtx();
        ctx.setThreadLocalInfo();
        StarRocksAssert starRocksAssert = new StarRocksAssert(ctx);
        TableName tblName = new TableName("test", "dup_table");
        String createTableSql = "CREATE TABLE " + tblName + " (colName String) DUPLICATE KEY(colName) " +
                "DISTRIBUTED BY HASH(colName) BUCKETS 1 " +
                "PROPERTIES('replication_num' = '1');";

        // create test.dup_table
        Assertions.assertDoesNotThrow(() -> starRocksAssert.withDatabase(tblName.getDb()).withTable(createTableSql));
        // rename column colName to colNameNew
        Assertions.assertDoesNotThrow(
                () -> starRocksAssert.alterTable("ALTER TABLE " + tblName + " RENAME COLUMN colName TO colNameNew;"));

        // send a delete statement "DELETE FROM test.dup_table WHERE colNameNew = 'a'"
        // Expect the delete condition to use columnId instead of logical name
        String deleteSql = "DELETE FROM " + tblName + " WHERE colNameNew = 'a'";
        DeleteStmt deleteStmt;
        try {
            deleteStmt = (DeleteStmt) UtFrameUtils.parseStmtWithNewParser(deleteSql, ctx);
        } catch (Exception e) {
            Assertions.fail("Don't expect exception: " + e.getMessage());
            return;
        }

        Table table = starRocksAssert.getTable(tblName.getDb(), tblName.getTbl());
        Assertions.assertNotNull(table);
        Column col = table.getColumn("colNameNew");
        Assertions.assertNotNull(col);
        Assertions.assertEquals("colNameNew", col.getName());
        Assertions.assertEquals("colName", col.getColumnId().getId());

        new MockUp<LakeDeleteJob>() {
            @Mock
            public void run(DeleteStmt stmt, Database db, Table table, List<Partition> partitions) {
                return;
            }
        };

        DeleteMgr mgr = GlobalStateMgr.getCurrentState().getDeleteMgr();
        Assertions.assertDoesNotThrow(() -> mgr.process(deleteStmt));
        Map<Long, DeleteJob> idToDeleteJob = Deencapsulation.getField(mgr, "idToDeleteJob");
        Assertions.assertEquals(1L, idToDeleteJob.size());

        idToDeleteJob.values().forEach(job -> {
            List<String> conditions = job.getDeleteInfo().getDeleteConditions();
            Assertions.assertEquals(1, conditions.size());
            // check the condition is using columnId
            Assertions.assertEquals("colName EQ \"a\"", conditions.get(0));
        });
    }
}
