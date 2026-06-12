//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Canonical license texts shown on the Acknowledgements detail screen. The MIT
/// and BSD templates take a copyright holder; Apache-2.0 is reproduced in full
/// (it carries no per-project copyright line in the body).
enum License {
    static func mit(holder: String) -> String {
        """
        MIT License

        Copyright (c) \(holder)

        Permission is hereby granted, free of charge, to any person obtaining a \
        copy of this software and associated documentation files (the \
        "Software"), to deal in the Software without restriction, including \
        without limitation the rights to use, copy, modify, merge, publish, \
        distribute, sublicense, and/or sell copies of the Software, and to \
        permit persons to whom the Software is furnished to do so, subject to \
        the following conditions:

        The above copyright notice and this permission notice shall be included \
        in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS \
        OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF \
        MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. \
        IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY \
        CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, \
        TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE \
        SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    }

    static func bsd2Clause(holder: String) -> String {
        """
        BSD 2-Clause License

        Copyright (c) \(holder)

        Redistribution and use in source and binary forms, with or without \
        modification, are permitted provided that the following conditions are \
        met:

        1. Redistributions of source code must retain the above copyright \
        notice, this list of conditions and the following disclaimer.

        2. Redistributions in binary form must reproduce the above copyright \
        notice, this list of conditions and the following disclaimer in the \
        documentation and/or other materials provided with the distribution.

        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS \
        IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED \
        TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A \
        PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT \
        HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, \
        SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED \
        TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR \
        PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF \
        LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING \
        NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS \
        SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
        """
    }

    static let apache2: String =
        """
        Apache License
        Version 2.0, January 2004
        http://www.apache.org/licenses/

        Licensed under the Apache License, Version 2.0 (the "License"); you may \
        not use this file except in compliance with the License. You may obtain \
        a copy of the License at

            http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software \
        distributed under the License is distributed on an "AS IS" BASIS, \
        WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or \
        implied. See the License for the specific language governing \
        permissions and limitations under the License.

        The full license text is available at the URL above.
        """
}
